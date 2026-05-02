from __future__ import annotations

import json
import logging
import os
import time
import random
import string
import base64
import hashlib
import hmac
import re
import secrets
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID

import boto3
import psycopg2
from botocore.exceptions import ClientError
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from psycopg2.extras import Json, RealDictCursor

from fl_coordinator import (
    ensure_fl_tables,
    register_fl_client,
    submit_masked_gradient,
    get_latest_model,
    get_fl_round_status,
    get_active_fl_round,
    list_active_fl_rounds,
    assign_client_to_fl_round,
    create_fl_round,
    aggregate_masked_gradients,
    get_convergence_metrics,
    complete_fl_round,
    FLClientRegistration,
    MaskedGradientUpload,
)


load_dotenv(dotenv_path=Path(__file__).with_name(".env"))
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://anora:anora@localhost:5432/anora")
DB_CONNECT_TIMEOUT_SECONDS = int(os.getenv("DB_CONNECT_TIMEOUT_SECONDS", "8"))
DB_CONNECT_RETRIES = int(os.getenv("DB_CONNECT_RETRIES", "6"))
DB_RETRY_DELAY_SECONDS = float(os.getenv("DB_RETRY_DELAY_SECONDS", "5"))
DB_READY = False
DB_INIT_ERROR: str | None = None
APP_STARTED_AT = datetime.now(timezone.utc)

# CORS primarily impacts browser clients. Native mobile clients are not blocked by CORS.
# In production, restrict to CloudFront CDN URL to prevent unauthorized access.
# If ALLOWED_ORIGINS='*', allow all origins and disable credentials for spec compliance.
_allowed_origins_raw = os.getenv("ALLOWED_ORIGINS", "https://d1p1fpleu1yzws.cloudfront.net").strip()
if _allowed_origins_raw == "*":
    ALLOWED_ORIGINS = ["*"]
    ALLOW_CREDENTIALS = False
else:
    ALLOWED_ORIGINS = [
        origin.strip()
        for origin in _allowed_origins_raw.split(",")
        if origin.strip()
    ]
    if not ALLOWED_ORIGINS:
        ALLOWED_ORIGINS = ["https://d1p1fpleu1yzws.cloudfront.net"]
    ALLOW_CREDENTIALS = True

logger = logging.getLogger("anora.backend")
logging.basicConfig(level=logging.INFO)

SNS_CLIENT: Any | None = None
SES_CLIENT: Any | None = None
ADMIN_MONITOR_API_KEY = os.getenv("ADMIN_MONITOR_API_KEY", "").strip()
if not ADMIN_MONITOR_API_KEY:
    logger.warning("admin_monitor_api_key_missing_fallback_clinician_auth_enabled")

EMAIL_REGEX = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
AUTH_JWT_ISSUER = "anora-backend"
AUTH_JWT_EXP_SECONDS = int(os.getenv("AUTH_JWT_EXP_SECONDS", "86400"))
OTP_TTL_SECONDS = int(os.getenv("OTP_TTL_SECONDS", "300"))
OTP_MAX_ATTEMPTS = int(os.getenv("OTP_MAX_ATTEMPTS", "5"))
OTP_DEBUG_ECHO = os.getenv("OTP_DEBUG_ECHO", "false").lower() == "true"
OTP_EMAIL_FROM = os.getenv("AWS_SES_FROM_EMAIL", "").strip()
OTP_EMAIL_SUBJECT = (
    os.getenv("OTP_EMAIL_SUBJECT", "Your Anora verification code").strip()
    or "Your Anora verification code"
)
DEMO_AUTH_DISABLED = os.getenv("DEMO_AUTH_DISABLED", "true").lower() == "true"
if DEMO_AUTH_DISABLED:
    logger.warning("demo_auth_bypass_enabled")


def _get_auth_jwt_secret() -> str:
    secret = os.getenv("AUTH_JWT_SECRET", "").strip()
    if secret:
        return secret

    # Development fallback. Set AUTH_JWT_SECRET in production.
    logger.warning("auth_jwt_secret_missing_using_dev_fallback")
    return "anora-dev-jwt-secret-change-me"


def _normalize_email(value: str) -> str:
    normalized = value.strip().lower()
    if not EMAIL_REGEX.match(normalized):
        raise ValueError("email must be a valid address, e.g. name@example.com")
    return normalized


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")


def _b64url_decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode(value + padding)


def _jwt_sign(payload: dict[str, Any]) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    header_b64 = _b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_b64 = _b64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    signature = hmac.new(
        _get_auth_jwt_secret().encode("utf-8"),
        signing_input,
        hashlib.sha256,
    ).digest()
    return f"{header_b64}.{payload_b64}.{_b64url_encode(signature)}"


def _jwt_decode_and_verify(token: str) -> dict[str, Any]:
    try:
        header_b64, payload_b64, signature_b64 = token.split(".")
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Malformed bearer token") from exc

    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    expected_sig = hmac.new(
        _get_auth_jwt_secret().encode("utf-8"),
        signing_input,
        hashlib.sha256,
    ).digest()
    provided_sig = _b64url_decode(signature_b64)
    if not hmac.compare_digest(expected_sig, provided_sig):
        raise HTTPException(status_code=401, detail="Invalid bearer token")

    try:
        payload_raw = _b64url_decode(payload_b64)
        payload = json.loads(payload_raw)
    except (ValueError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=401, detail="Invalid bearer token payload") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=401, detail="Invalid bearer token payload")

    exp = payload.get("exp")
    iss = payload.get("iss")
    if not isinstance(exp, int) or exp < int(datetime.now(timezone.utc).timestamp()):
        raise HTTPException(status_code=401, detail="Bearer token expired")
    if iss != AUTH_JWT_ISSUER:
        raise HTTPException(status_code=401, detail="Invalid token issuer")

    return payload


def _extract_bearer_token(request: Request) -> str:
    auth_header = request.headers.get("Authorization", "").strip()
    if not auth_header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = auth_header[7:].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    return token


def _require_auth_context(request: Request) -> dict[str, Any]:
    if DEMO_AUTH_DISABLED:
        auth_header = request.headers.get("Authorization", "").strip()
        if auth_header.lower().startswith("bearer "):
            token = auth_header[7:].strip()
            if token:
                try:
                    return _jwt_decode_and_verify(token)
                except HTTPException:
                    logger.warning("demo_auth_bypass_invalid_token_ignored")
        return {"role": "demo", "auth_bypassed": True}

    token = _extract_bearer_token(request)
    return _jwt_decode_and_verify(token)


def _require_clinician_context(request: Request, clinician_id: str) -> dict[str, Any]:
    if DEMO_AUTH_DISABLED:
        return {
            "role": "clinician",
            "clinician_id": clinician_id.strip(),
            "auth_bypassed": True,
        }

    claims = _require_auth_context(request)
    if claims.get("role") != "clinician":
        raise HTTPException(status_code=403, detail="Clinician role required")

    token_clinician_id = str(claims.get("clinician_id") or "").strip()
    requested_clinician_id = clinician_id.strip()
    if not token_clinician_id or token_clinician_id != requested_clinician_id:
        raise HTTPException(status_code=403, detail="Clinician identity mismatch")
    return claims


def _require_patient_context(request: Request, patient_device_id: str) -> dict[str, Any]:
    if DEMO_AUTH_DISABLED:
        return {
            "role": "patient",
            "patient_device_id": patient_device_id.strip(),
            "auth_bypassed": True,
        }

    claims = _require_auth_context(request)
    if claims.get("role") != "patient":
        raise HTTPException(status_code=403, detail="Patient role required")

    token_patient_device_id = str(claims.get("patient_device_id") or "").strip()
    requested_patient_device_id = patient_device_id.strip()
    if not token_patient_device_id or token_patient_device_id != requested_patient_device_id:
        raise HTTPException(status_code=403, detail="Patient identity mismatch")
    return claims


def _require_admin_access(request: Request) -> dict[str, Any]:
    """
    Authorize requests for admin monitoring and FL control endpoints.

    Preferred mode uses X-Admin-Key with ADMIN_MONITOR_API_KEY.
    Fallback mode (for backward compatibility) allows authenticated clinicians
    when an admin API key is not configured.
    """
    provided_admin_key = request.headers.get("X-Admin-Key", "").strip()
    if ADMIN_MONITOR_API_KEY:
        if not provided_admin_key or not secrets.compare_digest(
            provided_admin_key,
            ADMIN_MONITOR_API_KEY,
        ):
            raise HTTPException(status_code=403, detail="Invalid admin API key")
        return {"access": "admin_api_key"}

    if DEMO_AUTH_DISABLED:
        return {"access": "demo_auth_bypass"}

    claims = _require_auth_context(request)
    if claims.get("role") != "clinician":
        raise HTTPException(status_code=403, detail="Clinician role required")
    return claims


def _hash_otp_code(identity: str, code: str) -> str:
    material = f"{identity}:{code}".encode("utf-8")
    digest = hmac.new(
        _get_auth_jwt_secret().encode("utf-8"),
        material,
        hashlib.sha256,
    ).hexdigest()
    return digest


def _send_email_otp(email: str, otp_code: str) -> None:
    ses_client = _get_ses_client()
    if ses_client is None:
        logger.warning("otp_email_skipped_missing_ses_client email=%s", email)
        if not OTP_DEBUG_ECHO:
            raise HTTPException(
                status_code=503,
                detail="OTP email delivery is unavailable. Configure AWS_REGION and SES permissions.",
            )
        return

    if not OTP_EMAIL_FROM:
        raise HTTPException(
            status_code=503,
            detail="OTP email sender is not configured. Set AWS_SES_FROM_EMAIL.",
        )

    message = (
        f"Your Anora verification code is: {otp_code}. "
        f"It expires in {max(1, OTP_TTL_SECONDS // 60)} minute(s)."
    )

    try:
        ses_client.send_email(
            Source=OTP_EMAIL_FROM,
            Destination={"ToAddresses": [email]},
            Message={
                "Subject": {"Data": OTP_EMAIL_SUBJECT, "Charset": "UTF-8"},
                "Body": {
                    "Text": {
                        "Data": message,
                        "Charset": "UTF-8",
                    }
                },
            },
        )
    except ClientError as exc:
        logger.exception("otp_email_send_failed email=%s", email)
        raise HTTPException(status_code=502, detail="Failed to send OTP email") from exc


def get_connection() -> psycopg2.extensions.connection:
    return psycopg2.connect(
        DATABASE_URL,
        connect_timeout=DB_CONNECT_TIMEOUT_SECONDS,
    )


def _get_sns_client() -> Any | None:
    global SNS_CLIENT

    if SNS_CLIENT is not None:
        return SNS_CLIENT

    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
    if not region:
        logger.info("sns_push_disabled_missing_region")
        return None

    SNS_CLIENT = boto3.client("sns", region_name=region)
    return SNS_CLIENT


def _get_ses_client() -> Any | None:
    global SES_CLIENT

    if SES_CLIENT is not None:
        return SES_CLIENT

    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
    if not region:
        logger.info("ses_email_disabled_missing_region")
        return None

    SES_CLIENT = boto3.client("ses", region_name=region)
    return SES_CLIENT


def _normalize_platform(platform: str) -> str:
    normalized = platform.strip().lower()
    if normalized in {"ios", "iphone", "ipad"}:
        return "ios"
    if normalized in {"android"}:
        return "android"
    return normalized or "ios"


def _get_platform_application_arn(platform: str) -> str | None:
    normalized_platform = _normalize_platform(platform)
    if normalized_platform == "android":
        return os.getenv("AWS_SNS_PLATFORM_APPLICATION_ARN_ANDROID", "").strip() or None
    if normalized_platform == "ios":
        return os.getenv("AWS_SNS_PLATFORM_APPLICATION_ARN_IOS", "").strip() or None
    return os.getenv("AWS_SNS_PLATFORM_APPLICATION_ARN", "").strip() or None


def _get_clinician_push_endpoints(clinician_id: str) -> list[dict[str, str]]:
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT device_token, endpoint_arn, platform
                FROM clinician_push_endpoints
                WHERE clinician_id = %s
                ORDER BY last_seen_at DESC, created_at DESC;
                """,
                (clinician_id,),
            )
            rows = cursor.fetchall()

    endpoints = []
    for row in rows:
        token = str(row.get("device_token") or "").strip()
        endpoint_arn = str(row.get("endpoint_arn") or "").strip()
        platform = str(row.get("platform") or "ios").strip()
        if token and endpoint_arn:
            endpoints.append({"device_token": token, "endpoint_arn": endpoint_arn, "platform": platform})
    return endpoints


def _delete_clinician_push_endpoint(clinician_id: str, device_token: str) -> None:
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                DELETE FROM clinician_push_endpoints
                WHERE clinician_id = %s AND device_token = %s;
                """,
                (clinician_id, device_token),
            )


def _create_or_refresh_sns_endpoint(
    *,
    clinician_id: str,
    device_token: str,
    platform: str,
) -> str | None:
    sns_client = _get_sns_client()
    if sns_client is None:
        return None

    platform_application_arn = _get_platform_application_arn(platform)
    if not platform_application_arn:
        logger.info(
            "sns_push_disabled_missing_platform_application_arn clinician_id=%s platform=%s",
            clinician_id,
            platform,
        )
        return None

    response = sns_client.create_platform_endpoint(
        PlatformApplicationArn=platform_application_arn,
        Token=device_token,
        CustomUserData=clinician_id,
    )
    return response.get("EndpointArn")


def _dispatch_clinician_push_notification(
    *,
    clinician_id: str,
    alert_id: str,
    patient_device_id: str,
    priority: str,
) -> None:
    sns_client = _get_sns_client()
    if sns_client is None:
        return

    endpoints = _get_clinician_push_endpoints(clinician_id)
    if not endpoints:
        logger.info(
            "sns_push_skipped_no_tokens clinician_id=%s alert_id=%s",
            clinician_id,
            alert_id,
        )
        return

    message_body = json.dumps(
        {
            "default": "Urgent patient alert",
            "APNS": json.dumps(
                {
                    "aps": {
                        "alert": {
                            "title": "Urgent patient alert",
                            "body": "Open Anora to review the emergency alert.",
                        },
                        "sound": "default",
                    },
                    "event_type": "emergency_alert",
                    "alert_id": alert_id,
                    "clinician_id": clinician_id,
                    "patient_device_id": patient_device_id,
                    "priority": priority,
                }
            ),
            "APNS_SANDBOX": json.dumps(
                {
                    "aps": {
                        "alert": {
                            "title": "Urgent patient alert",
                            "body": "Open Anora to review the emergency alert.",
                        },
                        "sound": "default",
                    },
                    "event_type": "emergency_alert",
                    "alert_id": alert_id,
                    "clinician_id": clinician_id,
                    "patient_device_id": patient_device_id,
                    "priority": priority,
                }
            ),
        }
    )

    for endpoint in endpoints:
        try:
            sns_client.publish(
                TargetArn=endpoint["endpoint_arn"],
                MessageStructure="json",
                Message=message_body,
            )
            logger.info(
                "sns_push_sent clinician_id=%s alert_id=%s token_suffix=%s",
                clinician_id,
                alert_id,
                endpoint["device_token"][-8:],
            )
        except ClientError as exc:
            logger.exception(
                "sns_push_failed clinician_id=%s alert_id=%s",
                clinician_id,
                alert_id,
            )
            error_code = exc.response.get("Error", {}).get("Code", "")
            if error_code in {"EndpointDisabled", "InvalidParameter"}:
                _delete_clinician_push_endpoint(clinician_id, endpoint["device_token"])


def ensure_tables() -> None:
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto;")
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS reports (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                  clinician_id TEXT NOT NULL,
                  locked_box JSONB NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS clinicians (
                  clinician_id TEXT PRIMARY KEY,
                  public_key_pem TEXT NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS patient_links (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                  patient_device_id TEXT NOT NULL,
                  clinician_id TEXT NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW(),
                  UNIQUE (patient_device_id, clinician_id)
                );
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS mood_events (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                  patient_device_id TEXT NOT NULL,
                  clinician_id TEXT NOT NULL,
                  locked_box JSONB NOT NULL,
                  mood_score DOUBLE PRECISION,
                  mood_labels JSONB,
                  risk_flags JSONB,
                  event_timestamp TIMESTAMPTZ,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
                """
            )
            cursor.execute(
                """
                ALTER TABLE mood_events
                ADD COLUMN IF NOT EXISTS mood_score DOUBLE PRECISION;
                """
            )
            cursor.execute(
                """
                ALTER TABLE mood_events
                ADD COLUMN IF NOT EXISTS mood_labels JSONB;
                """
            )
            cursor.execute(
                """
                ALTER TABLE mood_events
                ADD COLUMN IF NOT EXISTS risk_flags JSONB;
                """
            )
            cursor.execute(
                """
                ALTER TABLE mood_events
                ADD COLUMN IF NOT EXISTS event_timestamp TIMESTAMPTZ;
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS shared_entries (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                  patient_device_id TEXT NOT NULL,
                  clinician_id TEXT NOT NULL,
                  locked_box JSONB NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS emergency_alerts (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                  patient_device_id TEXT NOT NULL,
                  clinician_id TEXT NOT NULL,
                  priority TEXT NOT NULL DEFAULT 'high',
                  locked_box JSONB NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS clinician_signals (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    patient_device_id TEXT NOT NULL,
                    clinician_id TEXT NOT NULL,
                    signal_type TEXT NOT NULL DEFAULT 'general',
                    locked_box JSONB NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                );
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS clinician_invite_codes (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    clinician_id TEXT NOT NULL REFERENCES clinicians(clinician_id),
                    code TEXT NOT NULL UNIQUE,
                    expires_at TIMESTAMPTZ NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    used_at TIMESTAMPTZ
                );
                """
            )
            cursor.execute(
                """
                                CREATE TABLE IF NOT EXISTS clinician_push_endpoints (
                  clinician_id TEXT NOT NULL REFERENCES clinicians(clinician_id) ON DELETE CASCADE,
                  device_token TEXT NOT NULL,
                  platform TEXT NOT NULL DEFAULT 'flutter',
                                    endpoint_arn TEXT,
                  created_at TIMESTAMPTZ DEFAULT NOW(),
                  updated_at TIMESTAMPTZ DEFAULT NOW(),
                  last_seen_at TIMESTAMPTZ DEFAULT NOW(),
                  UNIQUE (clinician_id, device_token)
                );
                """
            )
            cursor.execute(
                                "CREATE INDEX IF NOT EXISTS idx_clinician_push_endpoints_clinician_id ON clinician_push_endpoints (clinician_id);"
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_invite_code ON clinician_invite_codes (code);"
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS app_users (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                  email TEXT,
                  phone_number TEXT,
                  role TEXT NOT NULL CHECK (role IN ('patient', 'clinician')),
                  clinician_id TEXT,
                  patient_device_id TEXT,
                  created_at TIMESTAMPTZ DEFAULT NOW(),
                  updated_at TIMESTAMPTZ DEFAULT NOW(),
                  last_login_at TIMESTAMPTZ
                );
                """
            )
            cursor.execute(
                """
                ALTER TABLE app_users
                ADD COLUMN IF NOT EXISTS email TEXT;
                """
            )
            cursor.execute(
                """
                ALTER TABLE app_users
                ALTER COLUMN phone_number DROP NOT NULL;
                """
            )
            cursor.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_email_unique
                ON app_users (email);
                """
            )
            cursor.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_clinician_id_unique
                ON app_users (clinician_id)
                WHERE clinician_id IS NOT NULL;
                """
            )
            cursor.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_patient_device_id_unique
                ON app_users (patient_device_id)
                WHERE patient_device_id IS NOT NULL;
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS otp_challenges (
                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                    email TEXT,
                                    phone_number TEXT,
                  role TEXT NOT NULL CHECK (role IN ('patient', 'clinician')),
                  clinician_id TEXT,
                  patient_device_id TEXT,
                  otp_hash TEXT NOT NULL,
                  expires_at TIMESTAMPTZ NOT NULL,
                  attempts_remaining INTEGER NOT NULL DEFAULT 5,
                  consumed_at TIMESTAMPTZ,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
                """
            )
            cursor.execute(
                """
                ALTER TABLE otp_challenges
                ADD COLUMN IF NOT EXISTS email TEXT;
                """
            )
            cursor.execute(
                """
                ALTER TABLE otp_challenges
                ALTER COLUMN phone_number DROP NOT NULL;
                """
            )
            cursor.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_otp_challenges_email_created
                ON otp_challenges (email, created_at DESC);
                """
            )

    # Initialize FL tables
    ensure_fl_tables(connection)


def initialize_database_with_retries() -> None:
    global DB_READY, DB_INIT_ERROR
    for attempt in range(1, DB_CONNECT_RETRIES + 1):
        try:
            ensure_tables()
            logger.info("database_init_ok attempt=%s", attempt)
            DB_READY = True
            DB_INIT_ERROR = None
            return
        except psycopg2.OperationalError as exc:
            logger.exception(
                "database_init_retry_failed attempt=%s/%s",
                attempt,
                DB_CONNECT_RETRIES,
            )
            if attempt == DB_CONNECT_RETRIES:
                DB_READY = False
                DB_INIT_ERROR = (
                    "Could not connect to PostgreSQL. Verify DATABASE_URL, VPC routing, and security groups."
                )
                logger.error("database_init_failed_final %s", DB_INIT_ERROR)
                return
            time.sleep(DB_RETRY_DELAY_SECONDS)


@asynccontextmanager
async def lifespan(_: FastAPI):
    initialize_database_with_retries()
    yield


app = FastAPI(title="Anora Locked Box API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=ALLOW_CREDENTIALS,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ReportUpload(BaseModel):
    clinician_id: str = Field(min_length=1)
    locked_box: dict

    @field_validator("clinician_id")
    @classmethod
    def validate_clinician_id(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("clinician_id must be a non-empty string")
        return value.strip()

    @field_validator("locked_box")
    @classmethod
    def validate_locked_box(cls, value: dict) -> dict:
        required_keys = {"schema_version", "encrypted_payload", "encrypted_key"}
        missing = sorted(required_keys.difference(value.keys()))
        if missing:
            raise ValueError(
                f"locked_box is missing required keys: {', '.join(missing)}"
            )
        return value


class ClinicianRegistration(BaseModel):
    clinician_id: str = Field(min_length=1)
    public_key_pem: str = Field(min_length=1)

    @field_validator("clinician_id")
    @classmethod
    def validate_clinician_id(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("clinician_id must be a non-empty string")
        return value.strip()

    @field_validator("public_key_pem")
    @classmethod
    def validate_public_key_pem(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("public_key_pem must be a non-empty string")
        return value.strip()


class ClinicianPushTokenRegistration(BaseModel):
    clinician_id: str = Field(min_length=1)
    device_token: str = Field(min_length=1)
    platform: str = Field(default="flutter")

    @field_validator("clinician_id", "device_token")
    @classmethod
    def validate_required_string(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must be a non-empty string")
        return value.strip()

    @field_validator("platform")
    @classmethod
    def validate_platform(cls, value: str) -> str:
        trimmed = value.strip()
        return trimmed or "flutter"


class LinkRequest(BaseModel):
    patient_device_id: str = Field(min_length=1)
    clinician_id: str = Field(min_length=1)

    @field_validator("patient_device_id", "clinician_id")
    @classmethod
    def validate_non_empty(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must be a non-empty string")
        return value.strip()


class ClinicianIdPayload(BaseModel):
    clinician_id: str = Field(min_length=1)


class PatientLinkRequest(BaseModel):
    patient_device_id: str = Field(min_length=1)
    invite_code: str = Field(min_length=6, max_length=6)

    @field_validator("patient_device_id", "invite_code")
    @classmethod
    def validate_non_empty(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("must be a non-empty string")
        return stripped


class OTPStartRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    role: str = Field(min_length=6, max_length=9)
    clinician_id: str | None = None
    patient_device_id: str | None = None

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return _normalize_email(value)

    @field_validator("role")
    @classmethod
    def validate_role(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"patient", "clinician"}:
            raise ValueError("role must be either 'patient' or 'clinician'")
        return normalized

    @field_validator("clinician_id", "patient_device_id")
    @classmethod
    def validate_optional_ids(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed or None


class OTPVerifyRequest(BaseModel):
    challenge_id: str = Field(min_length=1)
    email: str = Field(min_length=5, max_length=255)
    otp_code: str = Field(min_length=6, max_length=6)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        return _normalize_email(value)

    @field_validator("otp_code")
    @classmethod
    def validate_otp_code(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized.isdigit():
            raise ValueError("otp_code must be numeric")
        return normalized


class SecurePayloadUpload(BaseModel):
    patient_device_id: str = Field(min_length=1)
    clinician_id: str = Field(min_length=1)
    locked_box: dict[str, Any]
    mood_summary: dict[str, Any] | None = None

    @field_validator("patient_device_id", "clinician_id")
    @classmethod
    def validate_non_empty(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must be a non-empty string")
        return value.strip()

    @field_validator("locked_box")
    @classmethod
    def validate_locked_box(cls, value: dict[str, Any]) -> dict[str, Any]:
        required_keys = {"schema_version", "encrypted_payload", "encrypted_key"}
        missing = sorted(required_keys.difference(value.keys()))
        if missing:
            raise ValueError(
                f"locked_box is missing required keys: {', '.join(missing)}"
            )
        return value

    @field_validator("mood_summary")
    @classmethod
    def validate_mood_summary(
        cls,
        value: dict[str, Any] | None,
    ) -> dict[str, Any] | None:
        if value is None:
            return None

        # Only mood metadata is allowed; never accept journal content.
        allowed_keys = {"timestamp", "mood_score", "mood_labels", "risk_flags"}
        disallowed_keys = {
            "text",
            "journal",
            "journal_text",
            "entry_text",
            "content",
            "raw_text",
        }

        for key in value.keys():
            key_lower = key.lower()
            if key_lower in disallowed_keys:
                raise ValueError("mood_summary must not include journal content")
            if key not in allowed_keys:
                raise ValueError(f"Unsupported mood_summary field: {key}")

        timestamp = value.get("timestamp")
        if timestamp is not None and not isinstance(timestamp, str):
            raise ValueError("mood_summary.timestamp must be an ISO datetime string")

        mood_score = value.get("mood_score")
        if mood_score is not None and not isinstance(mood_score, (int, float)):
            raise ValueError("mood_summary.mood_score must be numeric")

        mood_labels = value.get("mood_labels")
        if mood_labels is not None:
            if not isinstance(mood_labels, list) or not all(
                isinstance(item, str) for item in mood_labels
            ):
                raise ValueError(
                    "mood_summary.mood_labels must be a list of strings"
                )

        risk_flags = value.get("risk_flags")
        if risk_flags is not None:
            if not isinstance(risk_flags, list) or not all(
                isinstance(item, str) for item in risk_flags
            ):
                raise ValueError(
                    "mood_summary.risk_flags must be a list of strings"
                )

        return value


class ClinicianSignalUpload(SecurePayloadUpload):
    signal_type: str = Field(default="general", min_length=1, max_length=64)

    @field_validator("signal_type")
    @classmethod
    def validate_signal_type(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError("signal_type must be a non-empty string")
        return trimmed


def _issue_access_token(
    *,
    user_id: str,
    email: str,
    role: str,
    clinician_id: str | None,
    patient_device_id: str | None,
) -> tuple[str, datetime]:
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(seconds=AUTH_JWT_EXP_SECONDS)
    claims: dict[str, Any] = {
        "iss": AUTH_JWT_ISSUER,
        "sub": user_id,
        "email": email,
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
        "jti": secrets.token_urlsafe(18),
    }
    if clinician_id:
        claims["clinician_id"] = clinician_id
    if patient_device_id:
        claims["patient_device_id"] = patient_device_id

    return _jwt_sign(claims), expires_at


def _upsert_auth_user(
    *,
    email: str,
    role: str,
    clinician_id: str | None,
    patient_device_id: str | None,
) -> dict[str, Any]:
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT id, role, clinician_id, patient_device_id
                FROM app_users
                WHERE email = %s;
                """,
                (email,),
            )
            existing = cursor.fetchone()
            if existing is not None:
                existing_role = str(existing.get("role") or "").strip().lower()
                if existing_role and existing_role != role:
                    raise HTTPException(
                        status_code=409,
                        detail="Email already registered to a different role",
                    )

            cursor.execute(
                """
                INSERT INTO app_users (
                  email,
                  phone_number,
                  role,
                  clinician_id,
                  patient_device_id,
                  updated_at,
                  last_login_at
                )
                VALUES (%s, NULL, %s, %s, %s, NOW(), NOW())
                ON CONFLICT (email)
                DO UPDATE SET
                  role = EXCLUDED.role,
                  clinician_id = COALESCE(EXCLUDED.clinician_id, app_users.clinician_id),
                  patient_device_id = COALESCE(EXCLUDED.patient_device_id, app_users.patient_device_id),
                  updated_at = NOW(),
                  last_login_at = NOW()
                RETURNING id, email, role, clinician_id, patient_device_id;
                """,
                (
                    email,
                    role,
                    clinician_id,
                    patient_device_id,
                ),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to persist user session")
    return dict(row)


@app.post("/auth/otp/start")
def start_email_otp(payload: OTPStartRequest) -> dict[str, Any]:
    email = payload.email
    role = payload.role
    clinician_id = payload.clinician_id
    patient_device_id = payload.patient_device_id

    if role == "clinician" and (clinician_id is None or clinician_id.strip() == ""):
        raise HTTPException(status_code=422, detail="clinician_id is required for clinician auth")
    if role == "patient" and (patient_device_id is None or patient_device_id.strip() == ""):
        raise HTTPException(status_code=422, detail="patient_device_id is required for patient auth")

    otp_code = f"{random.randint(0, 999999):06d}"
    otp_hash = _hash_otp_code(email, otp_code)
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=OTP_TTL_SECONDS)

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                INSERT INTO otp_challenges (
                  email,
                  phone_number,
                  role,
                  clinician_id,
                  patient_device_id,
                  otp_hash,
                  expires_at,
                  attempts_remaining
                )
                VALUES (%s, NULL, %s, %s, %s, %s, %s, %s)
                RETURNING id;
                """,
                (
                    email,
                    role,
                    clinician_id,
                    patient_device_id,
                    otp_hash,
                    expires_at,
                    OTP_MAX_ATTEMPTS,
                ),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to create OTP challenge")

    _send_email_otp(email, otp_code)

    response: dict[str, Any] = {
        "challenge_id": str(row["id"]),
        "expires_in_seconds": OTP_TTL_SECONDS,
    }
    if OTP_DEBUG_ECHO:
        response["debug_otp"] = otp_code
    return response


@app.post("/auth/otp/verify")
def verify_email_otp(payload: OTPVerifyRequest) -> dict[str, Any]:
    challenge_id = payload.challenge_id.strip()
    email = payload.email
    otp_code = payload.otp_code

    now = datetime.now(timezone.utc)
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                  id,
                                    email,
                  phone_number,
                  role,
                  clinician_id,
                  patient_device_id,
                  otp_hash,
                  expires_at,
                  attempts_remaining,
                  consumed_at
                FROM otp_challenges
                                WHERE id = %s AND email = %s;
                """,
                                (challenge_id, email),
            )
            challenge = cursor.fetchone()

            if challenge is None:
                raise HTTPException(status_code=404, detail="OTP challenge not found")
            if challenge.get("consumed_at") is not None:
                raise HTTPException(status_code=410, detail="OTP challenge already used")
            expires_at = challenge.get("expires_at")
            if isinstance(expires_at, datetime) and expires_at < now:
                raise HTTPException(status_code=410, detail="OTP challenge expired")

            attempts_remaining = int(challenge.get("attempts_remaining") or 0)
            if attempts_remaining <= 0:
                raise HTTPException(status_code=429, detail="Too many OTP attempts")

            expected_hash = str(challenge.get("otp_hash") or "")
            actual_hash = _hash_otp_code(email, otp_code)
            if not hmac.compare_digest(expected_hash, actual_hash):
                cursor.execute(
                    """
                    UPDATE otp_challenges
                    SET attempts_remaining = GREATEST(attempts_remaining - 1, 0)
                    WHERE id = %s;
                    """,
                    (challenge_id,),
                )
                raise HTTPException(status_code=401, detail="Invalid OTP code")

            cursor.execute(
                """
                UPDATE otp_challenges
                SET consumed_at = NOW(), attempts_remaining = GREATEST(attempts_remaining - 1, 0)
                WHERE id = %s;
                """,
                (challenge_id,),
            )

    role = str(challenge.get("role") or "")
    clinician_id = challenge.get("clinician_id")
    patient_device_id = challenge.get("patient_device_id")

    user_row = _upsert_auth_user(
        email=email,
        role=role,
        clinician_id=clinician_id,
        patient_device_id=patient_device_id,
    )

    access_token, token_expires_at = _issue_access_token(
        user_id=str(user_row["id"]),
        email=str(user_row["email"]),
        role=str(user_row["role"]),
        clinician_id=(str(user_row.get("clinician_id")) if user_row.get("clinician_id") else None),
        patient_device_id=(str(user_row.get("patient_device_id")) if user_row.get("patient_device_id") else None),
    )

    return {
        "access_token": access_token,
        "token_type": "Bearer",
        "expires_at": token_expires_at.isoformat(),
        "user": {
            "user_id": str(user_row["id"]),
            "email": str(user_row["email"]),
            "role": str(user_row["role"]),
            "clinician_id": user_row.get("clinician_id"),
            "patient_device_id": user_row.get("patient_device_id"),
        },
    }


@app.get("/auth/me")
def auth_me(request: Request) -> dict[str, Any]:
    claims = _require_auth_context(request)
    return {
        "user_id": claims.get("sub"),
        "email": claims.get("email"),
        "role": claims.get("role"),
        "clinician_id": claims.get("clinician_id"),
        "patient_device_id": claims.get("patient_device_id"),
        "expires_at": claims.get("exp"),
    }


@app.post("/clinicians/register", status_code=201)
def register_clinician(payload: ClinicianRegistration, request: Request) -> dict[str, str]:
    _require_clinician_context(request, payload.clinician_id)
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO clinicians (clinician_id, public_key_pem)
                VALUES (%s, %s)
                ON CONFLICT (clinician_id)
                DO UPDATE SET public_key_pem = EXCLUDED.public_key_pem;
                """,
                (payload.clinician_id, payload.public_key_pem),
            )

    return {"clinician_id": payload.clinician_id, "status": "registered"}


@app.post("/clinicians/push-tokens", status_code=201)
def register_clinician_push_token(
    payload: ClinicianPushTokenRegistration,
    request: Request,
) -> dict[str, str]:
    _require_clinician_context(request, payload.clinician_id)
    endpoint_arn = _create_or_refresh_sns_endpoint(
        clinician_id=payload.clinician_id,
        device_token=payload.device_token,
        platform=payload.platform,
    )

    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO clinician_push_endpoints (
                  clinician_id,
                  device_token,
                  platform,
                  endpoint_arn,
                  created_at,
                  updated_at,
                  last_seen_at
                )
                VALUES (%s, %s, %s, %s, NOW(), NOW(), NOW())
                ON CONFLICT (clinician_id, device_token)
                DO UPDATE SET
                  platform = EXCLUDED.platform,
                  endpoint_arn = COALESCE(EXCLUDED.endpoint_arn, clinician_push_endpoints.endpoint_arn),
                  updated_at = NOW(),
                  last_seen_at = NOW();
                """,
                (
                    payload.clinician_id,
                    payload.device_token,
                    _normalize_platform(payload.platform),
                    endpoint_arn,
                ),
            )

    return {
        "clinician_id": payload.clinician_id,
        "device_token": payload.device_token,
        "status": "registered",
    }


@app.post("/reports", status_code=201)
def upload_report(payload: ReportUpload) -> dict[str, str]:
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                INSERT INTO reports (clinician_id, locked_box)
                VALUES (%s, %s)
                RETURNING id, clinician_id, created_at;
                """,
                (payload.clinician_id, Json(payload.locked_box)),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to store report")

    report_id = str(row["id"])
    logger.info(
        "stored_report report_id=%s clinician_id=%s created_at=%s",
        report_id,
        row["clinician_id"],
        row["created_at"],
    )
    return {"report_id": report_id, "status": "stored"}


@app.get("/reports/clinician/{clinician_id}")
def list_reports_for_clinician(
    request: Request,
    clinician_id: str,
    since: str | None = None,
    limit: int = 50,
) -> dict[str, Any]:
    _require_clinician_context(request, clinician_id)
    safe_limit = max(1, min(int(limit), 200))
    cid = clinician_id.strip()
    if not cid:
        raise HTTPException(status_code=422, detail="clinician_id required")

    query_parts = [
        "SELECT id, clinician_id, locked_box, created_at",
        "FROM reports",
        "WHERE clinician_id = %s",
    ]
    params: list[Any] = [cid]

    if since:
        try:
            since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
            if since_dt.tzinfo is None:
                since_dt = since_dt.replace(tzinfo=timezone.utc)
            query_parts.append("AND created_at > %s")
            params.append(since_dt)
        except ValueError as exc:
            raise HTTPException(
                status_code=422, detail="Invalid since format"
            ) from exc

    query_parts.extend(["ORDER BY created_at DESC", "LIMIT %s"])
    params.append(safe_limit)

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("\n".join(query_parts), tuple(params))
            rows = cur.fetchall()

    reports = []
    for row in rows:
        cat = row.get("created_at")
        cat_iso = (
            cat.astimezone(timezone.utc).isoformat()
            if isinstance(cat, datetime) else str(cat)
        )
        reports.append({
            "report_id": str(row["id"]),
            "clinician_id": str(row["clinician_id"]),
            "locked_box": row["locked_box"],
            "created_at": cat_iso,
            "source_type": "report",
        })

    return {"reports": reports}


@app.post("/clinicians/link", status_code=201)
def link_patient_to_clinician(payload: LinkRequest, request: Request) -> dict[str, Any]:
    _require_patient_context(request, payload.patient_device_id)
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT clinician_id, public_key_pem
                FROM clinicians
                WHERE clinician_id = %s;
                """,
                (payload.clinician_id,),
            )
            clinician = cursor.fetchone()

            if clinician is None:
                raise HTTPException(status_code=404, detail="Clinician not found")

            cursor.execute(
                """
                INSERT INTO patient_links (patient_device_id, clinician_id)
                VALUES (%s, %s)
                ON CONFLICT (patient_device_id, clinician_id)
                DO NOTHING;
                """,
                (payload.patient_device_id, payload.clinician_id),
            )

    return {
        "linked": True,
        "status": "securely_linked",
        "clinician_id": payload.clinician_id,
        "clinician_public_key_pem": str(clinician["public_key_pem"]),
    }


@app.post("/clinicians/generate-code", status_code=201)
def generate_invite_code(payload: ClinicianIdPayload, request: Request) -> dict[str, str]:
    """Generates a single-use invite code for a clinician."""
    clinician_id = payload.clinician_id.strip()
    if not clinician_id:
        raise HTTPException(status_code=422, detail="clinician_id is required")
    _require_clinician_context(request, clinician_id)

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("SELECT 1 FROM clinicians WHERE clinician_id = %s;", (clinician_id,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Clinician not found")

            # Generate a unique 6-character alphanumeric code
            while True:
                code = "".join(random.choices(string.ascii_uppercase + string.digits, k=6))
                cursor.execute("SELECT 1 FROM clinician_invite_codes WHERE code = %s AND expires_at > NOW();", (code,))
                if cursor.fetchone() is None:
                    break
            
            expires_at = datetime.now(timezone.utc) + timedelta(hours=24)
            
            cursor.execute(
                """
                INSERT INTO clinician_invite_codes (clinician_id, code, expires_at)
                VALUES (%s, %s, %s);
                """,
                (clinician_id, code, expires_at),
            )
    
    return {"invite_code": code, "expires_at": expires_at.isoformat()}


@app.post("/patients/link-with-code", status_code=201)
def link_patient_with_invite_code(payload: PatientLinkRequest, request: Request) -> dict[str, Any]:
    """Links a patient to a clinician using a single-use invite code."""
    _require_patient_context(request, payload.patient_device_id)
    invite_code = payload.invite_code.upper()
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                "SELECT clinician_id, expires_at, used_at FROM clinician_invite_codes WHERE code = %s;",
                (invite_code,),
            )
            invite = cursor.fetchone()

            if invite is None:
                raise HTTPException(status_code=404, detail="Invalid invite code.")
            if invite["used_at"] is not None:
                raise HTTPException(status_code=410, detail="Invite code has already been used.")
            if invite["expires_at"] < datetime.now(timezone.utc):
                raise HTTPException(status_code=410, detail="Invite code has expired.")

            clinician_id = invite["clinician_id"]
            
            cursor.execute("SELECT public_key_pem FROM clinicians WHERE clinician_id = %s;", (clinician_id,))
            clinician = cursor.fetchone()
            if clinician is None or not clinician["public_key_pem"]:
                raise HTTPException(status_code=404, detail="Clinician not found or has no public key.")

            # Mark code as used and create the link
            cursor.execute("UPDATE clinician_invite_codes SET used_at = NOW() WHERE code = %s;", (invite_code,))
            cursor.execute(
                "INSERT INTO patient_links (patient_device_id, clinician_id) VALUES (%s, %s) ON CONFLICT (patient_device_id, clinician_id) DO NOTHING;",
                (payload.patient_device_id, clinician_id),
            )

    return {
        "linked": True,
        "status": "securely_linked",
        "clinician_id": clinician_id,
        "clinician_public_key_pem": clinician["public_key_pem"],
    }


def _store_secure_event(table_name: str, payload: SecurePayloadUpload) -> str:
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                f"""
                INSERT INTO {table_name} (patient_device_id, clinician_id, locked_box)
                VALUES (%s, %s, %s)
                RETURNING id;
                """,
                (
                    payload.patient_device_id,
                    payload.clinician_id,
                    Json(payload.locked_box),
                ),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to store secure event")

    return str(row["id"])


@app.post("/telemetry/mood-events", status_code=201)
def upload_mood_event(payload: SecurePayloadUpload, request: Request) -> dict[str, str]:
    _require_patient_context(request, payload.patient_device_id)
    mood_summary = payload.mood_summary or {}
    mood_score_raw = mood_summary.get("mood_score")
    mood_score = float(mood_score_raw) if isinstance(mood_score_raw, (int, float)) else None

    mood_labels_raw = mood_summary.get("mood_labels")
    mood_labels = mood_labels_raw if isinstance(mood_labels_raw, list) else None

    risk_flags_raw = mood_summary.get("risk_flags")
    risk_flags = risk_flags_raw if isinstance(risk_flags_raw, list) else None

    event_timestamp: datetime | None = None
    timestamp_raw = mood_summary.get("timestamp")
    if isinstance(timestamp_raw, str) and timestamp_raw.strip():
        try:
            event_timestamp = datetime.fromisoformat(
                timestamp_raw.replace("Z", "+00:00")
            )
        except ValueError as exc:
            raise HTTPException(
                status_code=422,
                detail="Invalid mood_summary.timestamp format",
            ) from exc
        if event_timestamp.tzinfo is None:
            event_timestamp = event_timestamp.replace(tzinfo=timezone.utc)

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                INSERT INTO mood_events (
                  patient_device_id,
                  clinician_id,
                  locked_box,
                  mood_score,
                  mood_labels,
                  risk_flags,
                  event_timestamp
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id;
                """,
                (
                    payload.patient_device_id,
                    payload.clinician_id,
                    Json(payload.locked_box),
                    mood_score,
                    Json(mood_labels) if mood_labels is not None else None,
                    Json(risk_flags) if risk_flags is not None else None,
                    event_timestamp,
                ),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to store mood event")

    event_id = str(row["id"])
    return {"event_id": event_id, "status": "stored"}


@app.get("/telemetry/mood-events/latest/{clinician_id}")
def get_latest_mood_events(
    request: Request,
    clinician_id: str,
    limit: int = 100,
) -> dict[str, list[dict[str, Any]]]:
    _require_clinician_context(request, clinician_id)
    safe_limit = max(1, min(int(limit), 200))
    clinician_id_value = clinician_id.strip()
    if not clinician_id_value:
        raise HTTPException(status_code=422, detail="clinician_id is required")

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                WITH latest AS (
                  SELECT DISTINCT ON (patient_device_id)
                    id,
                    patient_device_id,
                    clinician_id,
                    mood_score,
                    mood_labels,
                    risk_flags,
                    event_timestamp,
                    created_at
                  FROM mood_events
                  WHERE clinician_id = %s
                  ORDER BY
                    patient_device_id,
                    COALESCE(event_timestamp, created_at) DESC,
                    created_at DESC
                )
                SELECT *
                FROM latest
                ORDER BY COALESCE(event_timestamp, created_at) DESC
                LIMIT %s;
                """,
                (clinician_id_value, safe_limit),
            )
            rows = cursor.fetchall()

    events: list[dict[str, Any]] = []
    for row in rows:
        created_at = row.get("created_at")
        created_at_iso = (
            created_at.astimezone(timezone.utc).isoformat()
            if isinstance(created_at, datetime)
            else str(created_at)
        )

        event_timestamp_raw = row.get("event_timestamp")
        event_timestamp_iso = (
            event_timestamp_raw.astimezone(timezone.utc).isoformat()
            if isinstance(event_timestamp_raw, datetime)
            else None
        )

        mood_labels_raw = row.get("mood_labels")
        mood_labels = mood_labels_raw if isinstance(mood_labels_raw, list) else []

        risk_flags_raw = row.get("risk_flags")
        risk_flags = risk_flags_raw if isinstance(risk_flags_raw, list) else []

        events.append(
            {
                "event_id": str(row.get("id")),
                "patient_device_id": str(row.get("patient_device_id")),
                "clinician_id": str(row.get("clinician_id")),
                "mood_score": row.get("mood_score"),
                "mood_labels": mood_labels,
                "risk_flags": risk_flags,
                "event_timestamp": event_timestamp_iso,
                "created_at": created_at_iso,
                "source_type": "mood_event",
            }
        )

    return {"events": events}


@app.get("/clinician/{clinician_id}/feed")
def get_clinician_feed(
    request: Request,
    clinician_id: str,
    since: str | None = None,
    limit: int = 100,
) -> dict[str, list[dict[str, Any]]]:
    """Fetches a consolidated, chronological feed of events for a clinician."""
    _require_clinician_context(request, clinician_id)
    safe_limit = max(1, min(int(limit), 500))
    clinician_id_value = clinician_id.strip()
    if not clinician_id_value:
        raise HTTPException(status_code=422, detail="clinician_id is required")

    # Base parameters and WHERE clauses for all subqueries
    query_params: list[Any] = [clinician_id_value]
    where_clauses = ["clinician_id = %s"]

    if since:
        try:
            since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
            if since_dt.tzinfo is None:
                since_dt = since_dt.replace(tzinfo=timezone.utc)
            where_clauses.append("created_at > %s")
            query_params.append(since_dt)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail="Invalid since format") from exc

    full_where_clause = " AND ".join(where_clauses)

    # The same set of parameters will be used for each of the three UNIONed SELECTs
    final_params = query_params * 3 + [safe_limit]

    query = f"""
        (
            SELECT
                id, patient_device_id, clinician_id, locked_box,
                mood_score, mood_labels, risk_flags, event_timestamp, created_at,
                'mood_event' AS source_type
            FROM mood_events
            WHERE {full_where_clause}
        )
        UNION ALL
        (
            SELECT
                id, patient_device_id, clinician_id, locked_box,
                NULL AS mood_score, NULL AS mood_labels, NULL AS risk_flags,
                NULL AS event_timestamp, created_at,
                'shared_entry' AS source_type
            FROM shared_entries
            WHERE {full_where_clause}
        )
        UNION ALL
        (
            SELECT
                id, patient_device_id, clinician_id, locked_box,
                NULL AS mood_score, NULL AS mood_labels, NULL AS risk_flags,
                NULL AS event_timestamp, created_at,
                'emergency_alert' AS source_type
            FROM emergency_alerts
            WHERE {full_where_clause}
        )
        ORDER BY COALESCE(event_timestamp, created_at) DESC
        LIMIT %s;
    """

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, tuple(final_params))
            rows = cursor.fetchall()

    feed_items: list[dict[str, Any]] = []
    for row in rows:
        created_at = row["created_at"]
        created_at_iso = (
            created_at.astimezone(timezone.utc).isoformat()
            if isinstance(created_at, datetime)
            else str(created_at)
        )

        event_timestamp_raw = row.get("event_timestamp")
        event_timestamp_iso = (
            event_timestamp_raw.astimezone(timezone.utc).isoformat()
            if isinstance(event_timestamp_raw, datetime)
            else None
        )

        item = {**row, "id": str(row["id"]), "created_at": created_at_iso, "event_timestamp": event_timestamp_iso}
        feed_items.append(item)

    return {"feed": feed_items}


@app.post("/entries/share", status_code=201)
def share_entry_content(payload: SecurePayloadUpload, request: Request) -> dict[str, str]:
    _require_patient_context(request, payload.patient_device_id)
    entry_id = _store_secure_event("shared_entries", payload)
    return {"entry_share_id": entry_id, "status": "stored"}


@app.post("/clinician/signal", status_code=201)
def upload_clinician_signal(payload: ClinicianSignalUpload, request: Request) -> dict[str, str]:
    _require_patient_context(request, payload.patient_device_id)
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                INSERT INTO clinician_signals (
                  patient_device_id,
                  clinician_id,
                  signal_type,
                  locked_box
                )
                VALUES (%s, %s, %s, %s)
                RETURNING id;
                """,
                (
                    payload.patient_device_id,
                    payload.clinician_id,
                    payload.signal_type,
                    Json(payload.locked_box),
                ),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to store clinician signal")

    return {"signal_id": str(row["id"]), "status": "stored"}


@app.post("/alerts/emergency", status_code=201)
def upload_emergency_alert(payload: SecurePayloadUpload, request: Request) -> dict[str, str]:
    _require_patient_context(request, payload.patient_device_id)
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                INSERT INTO emergency_alerts (
                  patient_device_id,
                  clinician_id,
                  priority,
                  locked_box
                )
                VALUES (%s, %s, 'high', %s)
                RETURNING id;
                """,
                (
                    payload.patient_device_id,
                    payload.clinician_id,
                    Json(payload.locked_box),
                ),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Failed to store emergency alert")

    alert_id = str(row["id"])
    _dispatch_clinician_push_notification(
        clinician_id=payload.clinician_id,
        alert_id=alert_id,
        patient_device_id=payload.patient_device_id,
        priority="high",
    )

    return {"alert_id": alert_id, "status": "stored"}


@app.get("/alerts/emergency/{clinician_id}")
def get_emergency_alerts(
    request: Request,
    clinician_id: str,
    since: str | None = None,
    limit: int = 100,
) -> dict[str, list[dict[str, str]]]:
    _require_clinician_context(request, clinician_id)
    query_parts = [
        "SELECT id, clinician_id, priority, created_at",
        "FROM emergency_alerts",
        "WHERE clinician_id = %s",
    ]
    params: list[Any] = [clinician_id.strip()]

    if since:
        try:
            since_value = datetime.fromisoformat(since.replace("Z", "+00:00"))
        except ValueError as exc:
            raise HTTPException(status_code=422, detail="Invalid since format") from exc
        if since_value.tzinfo is None:
            since_value = since_value.replace(tzinfo=timezone.utc)
        query_parts.append("AND created_at > %s")
        params.append(since_value)

    safe_limit = max(1, min(int(limit), 200))
    query_parts.append("ORDER BY created_at DESC")
    query_parts.append("LIMIT %s")
    params.append(safe_limit)

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("\n".join(query_parts), tuple(params))
            rows = cursor.fetchall()

    alerts = []
    for row in rows:
        created_at = row.get("created_at")
        if isinstance(created_at, datetime):
            created_at_iso = created_at.astimezone(timezone.utc).isoformat()
        else:
            created_at_iso = str(created_at)
        alerts.append(
            {
                "alert_id": str(row.get("id")),
                "clinician_id": str(row.get("clinician_id")),
                "priority": str(row.get("priority") or "high"),
                "created_at": created_at_iso,
                "source_type": "emergency_alert",
            }
        )

    return {"alerts": alerts}


@app.get("/reports/{report_id}")
def get_report(report_id: str, request: Request) -> dict[str, object]:
    """Returns a clinician report after validating clinician bearer token access."""
    claims = _require_auth_context(request)
    if claims.get("role") != "clinician":
        raise HTTPException(status_code=403, detail="Clinician role required")

    try:
        UUID(report_id)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Invalid report_id format") from exc

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT id, clinician_id, locked_box, created_at, 'report' AS source_type
                FROM reports
                WHERE id = %s;
                """,
                (report_id,),
            )
            row = cursor.fetchone()

            if row is None:
                cursor.execute(
                    """
                    SELECT id, clinician_id, locked_box, created_at, 'emergency_alert' AS source_type
                    FROM emergency_alerts
                    WHERE id = %s;
                    """,
                    (report_id,),
                )
                row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Report not found")

    token_clinician_id = str(claims.get("clinician_id") or "").strip()
    row_clinician_id = str(row.get("clinician_id") or "").strip()
    if not token_clinician_id or token_clinician_id != row_clinician_id:
        raise HTTPException(status_code=403, detail="Clinician identity mismatch")

    created_at = row["created_at"]
    if isinstance(created_at, datetime):
        created_at_iso = created_at.astimezone(timezone.utc).isoformat()
    else:
        created_at_iso = str(created_at)

    return {
        "report_id": str(row["id"]),
        "clinician_id": row["clinician_id"],
        "locked_box": row["locked_box"],
        "created_at": created_at_iso,
        "source_type": row.get("source_type", "report"),
    }


@app.get("/patients/linked/{clinician_id}")
def get_linked_patients(clinician_id: str, request: Request) -> dict[str, Any]:
    """
    Returns all patients linked to this clinician with their
    latest mood event joined via LATERAL subquery.
    """
    _require_clinician_context(request, clinician_id)
    cid = clinician_id.strip()
    if not cid:
        raise HTTPException(status_code=422, detail="clinician_id required")

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    pl.patient_device_id,
                    pl.created_at AS linked_at,
                    me.mood_score,
                    me.mood_labels,
                    me.risk_flags,
                    me.event_timestamp,
                    me.created_at AS last_mood_at,
                    mh.mood_history
                FROM patient_links pl
                LEFT JOIN LATERAL (
                    SELECT
                        mood_score,
                        mood_labels,
                        risk_flags,
                        event_timestamp,
                        created_at
                    FROM mood_events
                    WHERE patient_device_id = pl.patient_device_id
                      AND clinician_id = pl.clinician_id
                      AND mood_score IS NOT NULL
                    ORDER BY COALESCE(event_timestamp, created_at) DESC
                    LIMIT 1
                ) me ON true
                LEFT JOIN LATERAL (
                    SELECT jsonb_agg(history.mood_score ORDER BY history.order_key ASC) AS mood_history
                    FROM (
                        SELECT
                            mood_score,
                            COALESCE(event_timestamp, created_at) AS order_key
                        FROM mood_events
                        WHERE patient_device_id = pl.patient_device_id
                          AND clinician_id = pl.clinician_id
                          AND mood_score IS NOT NULL
                        ORDER BY COALESCE(event_timestamp, created_at) DESC
                        LIMIT 7
                    ) history
                ) mh ON true
                WHERE pl.clinician_id = %s
                ORDER BY
                    COALESCE(me.event_timestamp, me.created_at, pl.created_at)
                    DESC;
                """,
                (cid,),
            )
            rows = cur.fetchall()

    patients = []
    for row in rows:
        linked_at = row.get("linked_at")
        linked_at_iso = (
            linked_at.astimezone(timezone.utc).isoformat()
            if isinstance(linked_at, datetime) else str(linked_at)
        )

        latest_mood = None
        if row.get("last_mood_at") is not None:
            last_mood_at = row["last_mood_at"]
            last_mood_iso = (
                last_mood_at.astimezone(timezone.utc).isoformat()
                if isinstance(last_mood_at, datetime) else str(last_mood_at)
            )
            evt = row.get("event_timestamp")
            evt_iso = (
                evt.astimezone(timezone.utc).isoformat()
                if isinstance(evt, datetime) else None
            )
            mood_labels = row.get("mood_labels") or []
            risk_flags = row.get("risk_flags") or []
            latest_mood = {
                "mood_score": row.get("mood_score"),
                "mood_labels": mood_labels if isinstance(mood_labels, list) else [],
                "risk_flags": risk_flags if isinstance(risk_flags, list) else [],
                "event_timestamp": evt_iso,
                "last_mood_at": last_mood_iso,
            }

        mood_history = row.get("mood_history")
        mood_history_values: list[float] = []
        if isinstance(mood_history, list):
            for value in mood_history:
                if isinstance(value, (int, float)):
                    mood_history_values.append(float(value))

        patients.append({
            "patient_device_id": str(row["patient_device_id"]),
            "linked_at": linked_at_iso,
            "latest_mood": latest_mood,
            "mood_history": mood_history_values,
        })

    return {"patients": patients, "total": len(patients)}


# ===== Federated Learning Endpoints =====


@app.post("/fl/clients/register", status_code=201)
def register_fl_client_endpoint(payload: FLClientRegistration) -> dict[str, Any]:
    """
    Register a device for participation in federated learning.
    
    The device will receive the current model version and begin local training
    when idle/charging.
    """
    with get_connection() as connection:
        result = register_fl_client(connection, payload)
    
    logger.info(
        "fl_client_registered patient_device_id=%s app_version=%s model_version=%s",
        payload.patient_device_id,
        payload.app_version,
        payload.model_version,
    )
    
    return result


@app.get("/fl/models/latest")
def get_latest_fl_model() -> dict[str, Any]:
    """
    Download the latest deployed federated learning model.
    
    Returns the base64-encoded TFLite model weights that clients
    should use for local training.
    """
    with get_connection() as connection:
        model = get_latest_model(connection)
    
    if model is None:
        raise HTTPException(
            status_code=404,
            detail="No federated learning model available yet",
        )
    
    logger.info("fl_model_download model_version=%s", model["version"])
    return model


@app.post("/fl/gradients/submit", status_code=201)
def submit_fl_gradient(payload: MaskedGradientUpload) -> dict[str, Any]:
    """
    Submit masked gradients from local training.
    
    **Secure Aggregation (SecAgg) Protocol:**
    
    1. Device trains locally on journal entries (patient data never leaves device).
    2. Device computes gradient updates: dW_local = weights_new - weights_old
    3. Device generates random mask: R ~ N(0, sigma²)
    4. Device sends to server: masked_gradient = (dW_local + R)
    
    The server cannot recover individual device gradients because:
    - Each device's mask R is unknown to the server
    - When aggregating across 1000+ devices, masks statistically cancel: Σ(R_i) ≈ 0
    - Result: Σ(dW_i + R_i) ≈ Σ(dW_i), the true global average
    
    This enables privacy-preserving model improvement without centralizing data.
    """
    with get_connection() as connection:
        result = submit_masked_gradient(connection, payload)
    
    logger.info(
        "fl_gradient_received round_id=%s patient_device_id=%s gradient_norm=%.4f",
        payload.round_id,
        payload.patient_device_id,
        payload.gradient_norm,
    )
    
    return result


@app.get("/fl/rounds/active")
def get_active_fl_round_endpoint(
    patient_device_id: str | None = None,
    app_version: str | None = None,
) -> dict[str, Any]:
    """
    Get the currently active FL round.

    Clients should query this endpoint before submitting gradients so
    the coordinator can rotate rounds without requiring app updates.
    When patient_device_id is provided, coordinator uses sharding policy
    to return client-specific assignment across multiple active rounds.
    """
    with get_connection() as connection:
        if patient_device_id:
            status = assign_client_to_fl_round(
                connection,
                patient_device_id=patient_device_id,
                app_version=app_version,
            )
        else:
            status = get_active_fl_round(connection)

    if status is None:
        raise HTTPException(
            status_code=404,
            detail="No active federated learning round",
        )

    return status


@app.get("/fl/rounds/active/list")
def list_active_fl_rounds_endpoint() -> dict[str, Any]:
    """
    List all active FL rounds.

    Useful for observability and validating coordinator sharding state.
    """
    with get_connection() as connection:
        rounds = list_active_fl_rounds(connection)

    return {
        "rounds": rounds,
        "count": len(rounds),
    }


@app.get("/fl/rounds/{round_id}")
def get_fl_round_status_endpoint(round_id: int) -> dict[str, Any]:
    """
    Get aggregation progress for a specific federated learning round.
    
    Clients can poll this to understand if a round is complete and
    when new model updates will be available.
    """
    with get_connection() as connection:
        status = get_fl_round_status(connection, round_id)
    
    if status is None:
        raise HTTPException(
            status_code=404,
            detail=f"FL round {round_id} not found",
        )
    
    return status


@app.post("/fl/admin/rounds/create", status_code=201)
def create_fl_round_endpoint(
    request: Request,
    round_id: int,
    model_version: int,
    min_clients: int = 100,
) -> dict[str, Any]:
    """
    [Admin Endpoint] Create a new federated learning round.
    
    This initiates a new aggregation round. Clients will submit gradients
    for this round when they perform local training while idle/charging.
    """
    _require_admin_access(request)

    if round_id < 0 or model_version < 0:
        raise HTTPException(status_code=422, detail="Invalid round or model version")
    
    with get_connection() as connection:
        result = create_fl_round(connection, round_id, model_version, min_clients)
    
    logger.info(
        "fl_round_created round_id=%s model_version=%s min_clients=%s",
        round_id,
        model_version,
        min_clients,
    )
    
    return result


@app.post("/fl/admin/rounds/{round_id}/aggregate", status_code=200)
def aggregate_round_gradients(round_id: int, request: Request) -> dict[str, Any]:
    """
    [Admin Endpoint] Aggregate masked gradients for a completed round.
    
    This is called when a round has collected sufficient client gradients.
    It computes:
    - Aggregated gradient (element-wise average of masked vectors)
    - Convergence metrics (norms, variance)
    - Prepares updates for model training
    
    Security: Individual client gradients remain masked and cannot be recovered.
    Server only sees the aggregated signal across all clients.
    """
    _require_admin_access(request)

    if round_id < 0:
        raise HTTPException(status_code=422, detail="Invalid round_id")
    
    try:
        with get_connection() as connection:
            result = aggregate_masked_gradients(connection, round_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    
    logger.info(
        "fl_gradients_aggregated round_id=%s clients=%s avg_norm=%.4f std_dev=%.4f",
        round_id,
        result["num_clients"],
        result["avg_gradient_norm"],
        result["std_dev"],
    )
    
    return result


@app.get("/fl/rounds/{round_id}/metrics")
def get_round_convergence_metrics(round_id: int) -> dict[str, Any]:
    """
    Get convergence metrics for a specific FL round.
    
    Returns:
    - avg_gradient_norm: Average L2 norm of masked gradients
    - max_gradient_norm: Maximum norm (outlier detection)
    - gradient_std_dev: Standard deviation (convergence stability)
    - Trends: improving, stable, or diverging
    
    Use these to monitor training stability and decide when to deploy
    new global model.
    """
    if round_id < 0:
        raise HTTPException(status_code=422, detail="Invalid round_id")
    
    with get_connection() as connection:
        metrics = get_convergence_metrics(connection, round_id)
    
    return metrics


@app.post("/fl/admin/rounds/{round_id}/complete", status_code=200)
def complete_round(round_id: int, request: Request) -> dict[str, Any]:
    """
    [Admin Endpoint] Mark a round as completed.
    
    Call this after:
    1. Aggregation is done (gradients averaged)
    2. Global model has been trained with aggregated updates
    3. New model version is ready to deploy
    
    This prevents further gradient submissions to this round and
    allows starting a new round.
    """
    _require_admin_access(request)

    if round_id < 0:
        raise HTTPException(status_code=422, detail="Invalid round_id")
    
    try:
        with get_connection() as connection:
            result = complete_fl_round(connection, round_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    
    logger.info(
        "fl_round_completed round_id=%s model_version=%s clients=%s",
        round_id,
        result["model_version"],
        result["clients_submitted"],
    )
    
    return result


def _collect_fl_dashboard_overview(
    connection: psycopg2.extensions.connection,
) -> dict[str, Any]:
    """Collect federated learning dashboard metrics in one DB pass."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        # Client stats
        cursor.execute(
            """
            SELECT
                COUNT(*) AS total_clients,
                COUNT(CASE WHEN last_submission_at > NOW() - INTERVAL '7 days' THEN 1 END) AS active_7d,
                COUNT(CASE WHEN last_submission_at > NOW() - INTERVAL '30 days' THEN 1 END) AS active_30d,
                AVG(total_contributions) AS avg_contributions,
                MAX(total_contributions) AS max_contributions
            FROM fl_clients;
            """
        )
        client_stats = cursor.fetchone()

        # Round stats
        cursor.execute(
            """
            SELECT
                COUNT(*) FILTER (WHERE status = 'active') AS active_rounds,
                COUNT(*) FILTER (WHERE status = 'completed') AS completed_rounds,
                MAX(round_id) AS latest_round_id
            FROM fl_rounds;
            """
        )
        round_stats = cursor.fetchone()

        # Model stats
        cursor.execute(
            """
            SELECT
                MAX(version) AS latest_version,
                COUNT(*) AS total_versions,
                SUM(num_clients_aggregated) AS total_clients_contributed
            FROM fl_model_versions;
            """
        )
        model_stats = cursor.fetchone()

        # Latest round metrics
        round_stats = round_stats or {}
        client_stats = client_stats or {}
        model_stats = model_stats or {}
        latest_round = round_stats.get("latest_round_id") or 0
        cursor.execute(
            """
            SELECT metric_name, metric_value
            FROM fl_convergence_metrics
            WHERE round_id = %s;
            """,
            (latest_round,),
        )
        latest_metrics = cursor.fetchall()

    return {
        "clients": {
            "total": client_stats.get("total_clients") or 0,
            "active_7d": client_stats.get("active_7d") or 0,
            "active_30d": client_stats.get("active_30d") or 0,
            "avg_contributions": float(client_stats.get("avg_contributions") or 0),
            "max_contributions": client_stats.get("max_contributions") or 0,
        },
        "rounds": {
            "active": round_stats.get("active_rounds") or 0,
            "completed": round_stats.get("completed_rounds") or 0,
            "latest_id": round_stats.get("latest_round_id"),
        },
        "models": {
            "latest_version": model_stats.get("latest_version"),
            "total_versions": model_stats.get("total_versions") or 0,
            "total_clients_contributed": model_stats.get("total_clients_contributed") or 0,
        },
        "latest_round_metrics": {
            row["metric_name"]: float(row["metric_value"])
            for row in latest_metrics
        } if latest_metrics else {},
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/fl/dashboard/overview")
def fl_dashboard_overview(request: Request) -> dict[str, Any]:
    """
    [Admin Dashboard] Get federated learning system overview.

    Aggregates all key metrics for monitoring FL health:
    - Client participation (total, active, contribution rates)
    - Round status (active, completed)
    - Model versions and deployment status
    - Convergence metrics (latest round trends)
    """
    _require_admin_access(request)
    with get_connection() as connection:
        return _collect_fl_dashboard_overview(connection)


@app.get("/fl/dashboard/rounds")
def fl_dashboard_rounds(request: Request) -> dict[str, Any]:
    """
    [Admin Dashboard] Get detailed view of all FL rounds.
    
    Shows status, progress, and metrics for each round.
    Useful for monitoring ongoing aggregation and planning next round.
    """
    _require_admin_access(request)

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                  r.round_id,
                  r.model_version,
                  r.status,
                  r.min_clients,
                  r.clients_submitted,
                  ROUND(100.0 * r.clients_submitted / GREATEST(1, r.min_clients)) AS progress_percent,
                  r.created_at,
                  r.completed_at,
                  mv.num_clients_aggregated,
                  mv.avg_gradient_norm
                FROM fl_rounds r
                LEFT JOIN fl_model_versions mv ON r.model_version = mv.version
                ORDER BY r.round_id DESC;
                """
            )
            rounds = cursor.fetchall()

    return {
        "rounds": [
            {
                "round_id": row["round_id"],
                "model_version": row["model_version"],
                "status": row["status"],
                "clients_submitted": row["clients_submitted"],
                "min_clients": row["min_clients"],
                "progress_percent": row["progress_percent"],
                "created_at": row["created_at"].isoformat() if row["created_at"] else None,
                "completed_at": row["completed_at"].isoformat() if row["completed_at"] else None,
                "num_clients_aggregated": row["num_clients_aggregated"],
                "avg_gradient_norm": float(row["avg_gradient_norm"]) if row["avg_gradient_norm"] else None,
            }
            for row in rounds
        ],
        "count": len(rounds),
    }


@app.get("/fl/dashboard/clients")
def fl_dashboard_clients(request: Request, limit: int = 100) -> dict[str, Any]:
    """
    [Admin Dashboard] Get top contributing clients.
    
    Useful for identifying power users and checking device diversity.
    """
    _require_admin_access(request)

    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                  patient_device_id,
                  app_version,
                  current_model_version,
                  total_contributions,
                  last_submission_at,
                  enrolled_at
                FROM fl_clients
                ORDER BY total_contributions DESC, last_submission_at DESC
                LIMIT %s;
                """,
                (limit,),
            )
            clients = cursor.fetchall()

    return {
        "clients": [
            {
                "device_id": row["patient_device_id"],
                "app_version": row["app_version"],
                "model_version": row["current_model_version"],
                "contributions": row["total_contributions"],
                "last_submission": row["last_submission_at"].isoformat() if row["last_submission_at"] else None,
                "enrolled": row["enrolled_at"].isoformat() if row["enrolled_at"] else None,
            }
            for row in clients
        ],
        "count": len(clients),
    }


def _build_health_snapshot() -> dict[str, Any]:
    """Build current health state with an active database connectivity check."""
    response = {
        "status": "ok",
        "db_ready": DB_READY,
        "db_connected": False,
        "db_error": None,
    }

    if DB_READY:
        try:
            conn = get_connection()
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1;")
            conn.close()
            response["db_connected"] = True
            response["status"] = "ok"
        except psycopg2.OperationalError as exc:
            response["db_connected"] = False
            response["status"] = "degraded"
            response["db_error"] = f"connection_failed: {str(exc)[:100]}"
    else:
        response["status"] = "degraded"
        response["db_error"] = DB_INIT_ERROR or "database initialization failed"

    return response


@app.get("/admin/monitor/overview")
def admin_monitor_overview(request: Request) -> dict[str, Any]:
    """
    Get a single-view operational dashboard for admin monitoring and demos.

    Includes service health, authentication activity, care data activity,
    federated learning metrics, and recent event feed snapshots.
    """
    _require_admin_access(request)

    now = datetime.now(timezone.utc)
    health_status = _build_health_snapshot()
    uptime_seconds = max(0, int((now - APP_STARTED_AT).total_seconds()))

    overview: dict[str, Any] = {
        "service": {
            "status": health_status["status"],
            "db_ready": health_status["db_ready"],
            "db_connected": health_status["db_connected"],
            "db_error": health_status["db_error"],
            "started_at": APP_STARTED_AT.isoformat(),
            "uptime_seconds": uptime_seconds,
            "deployment_env": os.getenv("DEPLOYMENT_ENV", "unknown"),
            "app_version": os.getenv("APP_VERSION", "unknown"),
            "admin_access_mode": "admin_api_key" if ADMIN_MONITOR_API_KEY else "clinician_token_fallback",
        },
        "auth": {
            "users_total": 0,
            "users_patients": 0,
            "users_clinicians": 0,
            "users_active_24h": 0,
            "otp_requested_1h": 0,
            "otp_verified_1h": 0,
            "otp_pending": 0,
            "otp_expired": 0,
            "otp_locked_out": 0,
        },
        "activity": {
            "patient_links_total": 0,
            "reports_total": 0,
            "reports_24h": 0,
            "mood_events_24h": 0,
            "emergency_alerts_24h": 0,
        },
        "federated_learning": {},
        "recent_events": [],
        "timestamp": now.isoformat(),
    }

    try:
        with get_connection() as connection:
            with connection.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute(
                    """
                    SELECT
                      (SELECT COUNT(*) FROM app_users) AS users_total,
                      (SELECT COUNT(*) FROM app_users WHERE role = 'patient') AS users_patients,
                      (SELECT COUNT(*) FROM app_users WHERE role = 'clinician') AS users_clinicians,
                      (SELECT COUNT(*) FROM app_users WHERE last_login_at > NOW() - INTERVAL '24 hours') AS users_active_24h,
                      (SELECT COUNT(*) FROM otp_challenges WHERE created_at > NOW() - INTERVAL '1 hour') AS otp_requested_1h,
                      (SELECT COUNT(*) FROM otp_challenges WHERE consumed_at IS NOT NULL AND consumed_at > NOW() - INTERVAL '1 hour') AS otp_verified_1h,
                      (SELECT COUNT(*) FROM otp_challenges WHERE consumed_at IS NULL AND expires_at > NOW()) AS otp_pending,
                      (SELECT COUNT(*) FROM otp_challenges WHERE consumed_at IS NULL AND expires_at <= NOW()) AS otp_expired,
                      (SELECT COUNT(*) FROM otp_challenges WHERE consumed_at IS NULL AND attempts_remaining <= 0) AS otp_locked_out,
                      (SELECT COUNT(*) FROM patient_links) AS patient_links_total,
                      (SELECT COUNT(*) FROM reports) AS reports_total,
                      (SELECT COUNT(*) FROM reports WHERE created_at > NOW() - INTERVAL '24 hours') AS reports_24h,
                      (SELECT COUNT(*) FROM mood_events WHERE created_at > NOW() - INTERVAL '24 hours') AS mood_events_24h,
                      (SELECT COUNT(*) FROM emergency_alerts WHERE created_at > NOW() - INTERVAL '24 hours') AS emergency_alerts_24h;
                    """
                )
                summary = cursor.fetchone() or {}

                cursor.execute(
                    """
                    SELECT event_type, subject, event_time
                    FROM (
                        SELECT 'report_uploaded' AS event_type, clinician_id AS subject, created_at AS event_time FROM reports
                        UNION ALL
                        SELECT 'mood_event_recorded' AS event_type, patient_device_id AS subject, created_at AS event_time FROM mood_events
                        UNION ALL
                        SELECT 'emergency_alert_created' AS event_type, clinician_id AS subject, created_at AS event_time FROM emergency_alerts
                        UNION ALL
                        SELECT 'otp_requested' AS event_type, COALESCE(email, phone_number) AS subject, created_at AS event_time FROM otp_challenges
                        UNION ALL
                        SELECT 'otp_verified' AS event_type, COALESCE(email, phone_number) AS subject, consumed_at AS event_time
                        FROM otp_challenges
                        WHERE consumed_at IS NOT NULL
                    ) events
                    WHERE event_time IS NOT NULL
                    ORDER BY event_time DESC
                    LIMIT 12;
                    """
                )
                recent_events = cursor.fetchall() or []

            overview["federated_learning"] = _collect_fl_dashboard_overview(connection)

            overview["auth"] = {
                "users_total": summary.get("users_total") or 0,
                "users_patients": summary.get("users_patients") or 0,
                "users_clinicians": summary.get("users_clinicians") or 0,
                "users_active_24h": summary.get("users_active_24h") or 0,
                "otp_requested_1h": summary.get("otp_requested_1h") or 0,
                "otp_verified_1h": summary.get("otp_verified_1h") or 0,
                "otp_pending": summary.get("otp_pending") or 0,
                "otp_expired": summary.get("otp_expired") or 0,
                "otp_locked_out": summary.get("otp_locked_out") or 0,
            }

            overview["activity"] = {
                "patient_links_total": summary.get("patient_links_total") or 0,
                "reports_total": summary.get("reports_total") or 0,
                "reports_24h": summary.get("reports_24h") or 0,
                "mood_events_24h": summary.get("mood_events_24h") or 0,
                "emergency_alerts_24h": summary.get("emergency_alerts_24h") or 0,
            }

            overview["recent_events"] = [
                {
                    "event_type": row.get("event_type"),
                    "subject": row.get("subject"),
                    "event_time": row["event_time"].isoformat() if row.get("event_time") else None,
                }
                for row in recent_events
            ]
    except psycopg2.Error as exc:
        logger.exception("admin_monitor_overview_query_failed")
        overview["data_source_error"] = str(exc).splitlines()[0][:180]

    return overview


@app.get("/fl/clients/stats")
def get_fl_client_stats() -> dict[str, Any]:
    """
    Get federated learning engagement statistics.
    
    Useful for monitoring FL participation and planning aggregation rounds.
    """
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """
                SELECT
                  COUNT(*) AS total_clients,
                  COUNT(CASE WHEN last_submission_at > NOW() - INTERVAL '7 days' THEN 1 END) AS active_clients_7d,
                  AVG(total_contributions) AS avg_contributions,
                  MAX(total_contributions) AS max_contributions
                FROM fl_clients;
                """
            )
            row = cursor.fetchone()
            row = row or {}

    return {
        "total_clients": row.get("total_clients") or 0,
        "active_clients_7d": row.get("active_clients_7d") or 0,
        "avg_contributions": float(row.get("avg_contributions") or 0),
        "max_contributions": row.get("max_contributions") or 0,
    }


@app.get("/health", response_model=None)
def health() -> dict[str, Any]:
    """
    Health check endpoint for monitoring and load balancers.
    
    Returns:
      - status: "ok" (DB connected) or "degraded" (DB disconnected)
      - db_ready: True if initialization succeeded, False otherwise
      - db_connected: True if current connectivity test succeeds
      - db_error: Reason for degraded state (if applicable)
    """
    return _build_health_snapshot()
