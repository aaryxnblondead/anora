from __future__ import annotations

import json
import logging
import os
import time
import random
import string
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID

import boto3
import psycopg2
from botocore.exceptions import ClientError
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from psycopg2.extras import Json, RealDictCursor


load_dotenv(dotenv_path=Path(__file__).with_name(".env"))
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://anora:anora@localhost:5432/anora")
DB_CONNECT_TIMEOUT_SECONDS = int(os.getenv("DB_CONNECT_TIMEOUT_SECONDS", "8"))
DB_CONNECT_RETRIES = int(os.getenv("DB_CONNECT_RETRIES", "6"))
DB_RETRY_DELAY_SECONDS = float(os.getenv("DB_RETRY_DELAY_SECONDS", "5"))
DB_READY = False
DB_INIT_ERROR: str | None = None

# CORS primarily impacts browser clients. Native mobile clients are not blocked by CORS.
# If ALLOWED_ORIGINS='*', allow all origins and disable credentials for spec compliance.
_allowed_origins_raw = os.getenv("ALLOWED_ORIGINS", "*").strip()
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
        ALLOWED_ORIGINS = ["http://localhost:3000"]
    ALLOW_CREDENTIALS = True

logger = logging.getLogger("anora.backend")
logging.basicConfig(level=logging.INFO)

SNS_CLIENT: Any | None = None


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


@app.post("/clinicians/register", status_code=201)
def register_clinician(payload: ClinicianRegistration) -> dict[str, str]:
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
) -> dict[str, str]:
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
    clinician_id: str,
    since: str | None = None,
    limit: int = 50,
) -> dict[str, Any]:
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
def link_patient_to_clinician(payload: LinkRequest) -> dict[str, Any]:
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
def generate_invite_code(payload: ClinicianIdPayload) -> dict[str, str]:
    """Generates a single-use invite code for a clinician."""
    clinician_id = payload.clinician_id.strip()
    if not clinician_id:
        raise HTTPException(status_code=422, detail="clinician_id is required")

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
def link_patient_with_invite_code(payload: PatientLinkRequest) -> dict[str, Any]:
    """Links a patient to a clinician using a single-use invite code."""
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
def upload_mood_event(payload: SecurePayloadUpload) -> dict[str, str]:
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
    clinician_id: str,
    limit: int = 100,
) -> dict[str, list[dict[str, Any]]]:
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
    clinician_id: str,
    since: str | None = None,
    limit: int = 100,
) -> dict[str, list[dict[str, Any]]]:
    """Fetches a consolidated, chronological feed of events for a clinician."""
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
def share_entry_content(payload: SecurePayloadUpload) -> dict[str, str]:
    entry_id = _store_secure_event("shared_entries", payload)
    return {"entry_share_id": entry_id, "status": "stored"}


@app.post("/clinician/signal", status_code=201)
def upload_clinician_signal(payload: ClinicianSignalUpload) -> dict[str, str]:
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
def upload_emergency_alert(payload: SecurePayloadUpload) -> dict[str, str]:
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
    clinician_id: str,
    since: str | None = None,
    limit: int = 100,
) -> dict[str, list[dict[str, str]]]:
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
def get_report(report_id: str) -> dict[str, object]:
    """MVP endpoint without authentication. TODO: Add clinician JWT auth before production."""
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
def get_linked_patients(clinician_id: str) -> dict[str, Any]:
    """
    Returns all patients linked to this clinician with their
    latest mood event joined via LATERAL subquery.
    """
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


@app.get("/health")
def health() -> dict[str, str | bool]:
    if DB_READY:
        return {"status": "ok", "db_ready": True}
    return {
        "status": "degraded",
        "db_ready": False,
        "db_error": DB_INIT_ERROR or "database initialization failed",
    }
