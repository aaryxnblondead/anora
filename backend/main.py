from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import UUID

import psycopg2
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from psycopg2.extras import Json, RealDictCursor


load_dotenv(dotenv_path=Path(__file__).with_name(".env"))
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://anora:BrEdPk2825@localhost:5432/anora")

# In production, set ALLOWED_ORIGINS to the deployed frontend origin(s).
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
    if origin.strip()
]

logger = logging.getLogger("anora.backend")
logging.basicConfig(level=logging.INFO)


def get_connection() -> psycopg2.extensions.connection:
    return psycopg2.connect(DATABASE_URL)


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
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
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


@asynccontextmanager
async def lifespan(_: FastAPI):
    ensure_tables()
    yield


app = FastAPI(title="Anora Locked Box API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
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


class LinkRequest(BaseModel):
    patient_device_id: str = Field(min_length=1)
    clinician_id: str = Field(min_length=1)

    @field_validator("patient_device_id", "clinician_id")
    @classmethod
    def validate_non_empty(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must be a non-empty string")
        return value.strip()


class SecurePayloadUpload(BaseModel):
    patient_device_id: str = Field(min_length=1)
    clinician_id: str = Field(min_length=1)
    locked_box: dict[str, Any]

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


@app.post("/clinicians/link", status_code=201)
def link_patient_to_clinician(payload: LinkRequest) -> dict[str, str | bool]:
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
    event_id = _store_secure_event("mood_events", payload)
    return {"event_id": event_id, "status": "stored"}


@app.post("/entries/share", status_code=201)
def share_entry_content(payload: SecurePayloadUpload) -> dict[str, str]:
    entry_id = _store_secure_event("shared_entries", payload)
    return {"entry_share_id": entry_id, "status": "stored"}


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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
