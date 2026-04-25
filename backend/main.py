from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from uuid import UUID

import psycopg2
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from psycopg2.extras import Json, RealDictCursor


load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://anora:anora@localhost:5432/anora")
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
    if origin.strip()
]

logger = logging.getLogger("anora.backend")
logging.basicConfig(level=logging.INFO)


def get_connection() -> psycopg2.extensions.connection:
    return psycopg2.connect(DATABASE_URL)


def ensure_reports_table() -> None:
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


@asynccontextmanager
async def lifespan(_: FastAPI):
    ensure_reports_table()
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
                SELECT id, clinician_id, locked_box, created_at
                FROM reports
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
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
