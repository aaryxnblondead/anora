
from __future__ import annotations

import hashlib
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import Any
from uuid import UUID

import psycopg2
from psycopg2.extras import Json, RealDictCursor
from pydantic import BaseModel, Field, field_validator

logger = logging.getLogger("anora.fl_coordinator")


class FLClientRegistration(BaseModel):
    """Register a device for federated learning."""
    patient_device_id: str = Field(min_length=1)
    app_version: str = Field(min_length=1, max_length=20)
    model_version: int = Field(ge=0)

    @field_validator("patient_device_id", "app_version")
    @classmethod
    def validate_non_empty(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must be a non-empty string")
        return value.strip()


class MaskedGradientUpload(BaseModel):
    """
    Submit masked gradients from a client.
    
    The gradient vector is masked using SecAgg:
    - Client generates random mask R and adds it to local gradients: (dW + R)
    - Server receives masked gradients from multiple clients
    - Server cannot recover individual client gradients
    - When summed across 1000+ clients, masks cancel mathematically
    """
    patient_device_id: str = Field(min_length=1)
    round_id: int = Field(ge=0)
    model_version: int = Field(ge=0)
    masked_gradient: list[float]
    gradient_norm: float = Field(ge=0.0)  # For convergence monitoring
    num_local_steps: int = Field(ge=1)  # Local training iterations before masking
    timestamp: str  # ISO format timestamp

    @field_validator("patient_device_id")
    @classmethod
    def validate_device_id(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("patient_device_id must be a non-empty string")
        return value.strip()

    @field_validator("masked_gradient")
    @classmethod
    def validate_masked_gradient(cls, value: list[float]) -> list[float]:
        if not value:
            raise ValueError("masked_gradient must not be empty")
        return value

    @field_validator("timestamp")
    @classmethod
    def validate_timestamp(cls, value: str) -> str:
        try:
            datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError("timestamp must be valid ISO format") from exc
        return value


class FLModelMetadata(BaseModel):
    """Metadata for a federated learning model version."""
    version: int
    base64_weights: str = Field(min_length=100)  # Base64-encoded TFLite weights
    architecture_hash: str = Field(min_length=32, max_length=64)
    training_round: int = Field(ge=0)
    num_clients_aggregated: int = Field(ge=0)
    created_at: str

    @field_validator("base64_weights", "architecture_hash")
    @classmethod
    def validate_fields(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must be a non-empty string")
        return value.strip()


def ensure_fl_tables(connection: psycopg2.extensions.connection) -> None:
    """Create FL-specific database tables."""
    with connection.cursor() as cursor:
        # Track FL clients
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS fl_clients (
              patient_device_id TEXT PRIMARY KEY,
              app_version TEXT NOT NULL,
              current_model_version INT NOT NULL DEFAULT 0,
              assigned_round_id INT,
              assignment_expires_at TIMESTAMPTZ,
              last_submission_at TIMESTAMPTZ,
              total_contributions INT NOT NULL DEFAULT 0,
              enrolled_at TIMESTAMPTZ DEFAULT NOW(),
              updated_at TIMESTAMPTZ DEFAULT NOW()
            );
            """
        )

        # Backward-compatible schema evolution for existing deployments.
        cursor.execute(
            "ALTER TABLE fl_clients ADD COLUMN IF NOT EXISTS assigned_round_id INT;"
        )
        cursor.execute(
            "ALTER TABLE fl_clients ADD COLUMN IF NOT EXISTS assignment_expires_at TIMESTAMPTZ;"
        )

        # Track FL training rounds
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS fl_rounds (
              round_id INT PRIMARY KEY,
              model_version INT NOT NULL UNIQUE,
              status TEXT NOT NULL DEFAULT 'active',  -- active, completed, superseded
              min_clients INT NOT NULL DEFAULT 100,
              clients_submitted INT NOT NULL DEFAULT 0,
              created_at TIMESTAMPTZ DEFAULT NOW(),
              completed_at TIMESTAMPTZ,
              updated_at TIMESTAMPTZ DEFAULT NOW()
            );
            """
        )

        # Store masked gradients per client per round
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS fl_gradients (
              id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
              round_id INT NOT NULL REFERENCES fl_rounds(round_id) ON DELETE CASCADE,
              patient_device_id TEXT NOT NULL,
              model_version INT NOT NULL,
              masked_gradient JSONB NOT NULL,  -- Base64-encoded masked parameter updates
              gradient_norm DOUBLE PRECISION,
              num_local_steps INT,
              submitted_at TIMESTAMPTZ DEFAULT NOW(),
              UNIQUE (round_id, patient_device_id)  -- One gradient per client per round
            );
            """
        )

        # Track FL model versions
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS fl_model_versions (
              version INT PRIMARY KEY,
              base64_weights TEXT NOT NULL,  -- Serialized and base64-encoded TFLite model
              architecture_hash TEXT NOT NULL,  -- Hash to detect compatibility issues
              training_round INT NOT NULL REFERENCES fl_rounds(round_id),
              num_clients_aggregated INT NOT NULL,
              avg_gradient_norm DOUBLE PRECISION,
              created_at TIMESTAMPTZ DEFAULT NOW(),
              deployed_at TIMESTAMPTZ
            );
            """
        )

        # Track convergence metrics per round
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS fl_convergence_metrics (
              id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
              round_id INT NOT NULL REFERENCES fl_rounds(round_id) ON DELETE CASCADE,
              metric_name TEXT NOT NULL,  -- avg_gradient_norm, max_gradient_norm, loss, accuracy
              metric_value DOUBLE PRECISION NOT NULL,
              recorded_at TIMESTAMPTZ DEFAULT NOW()
            );
            """
        )

        # Create indices for query performance
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_fl_gradients_round ON fl_gradients(round_id);"
        )
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_fl_gradients_device ON fl_gradients(patient_device_id);"
        )
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_fl_clients_updated ON fl_clients(updated_at DESC);"
        )
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_fl_clients_assigned_round ON fl_clients(assigned_round_id);"
        )
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_fl_convergence_round ON fl_convergence_metrics(round_id);"
        )

    connection.commit()


def register_fl_client(
    connection: psycopg2.extensions.connection,
    payload: FLClientRegistration,
) -> dict[str, Any]:
    """Register or update a client for federated learning."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            INSERT INTO fl_clients (patient_device_id, app_version, current_model_version, updated_at)
            VALUES (%s, %s, %s, NOW())
            ON CONFLICT (patient_device_id)
            DO UPDATE SET
              app_version = EXCLUDED.app_version,
              current_model_version = EXCLUDED.current_model_version,
              updated_at = NOW()
            RETURNING patient_device_id, current_model_version, total_contributions, enrolled_at;
            """,
            (payload.patient_device_id, payload.app_version, payload.model_version),
        )
        row = cursor.fetchone()

    if row is None:
        raise RuntimeError("Failed to register FL client")

    return {
        "patient_device_id": row["patient_device_id"],
        "current_model_version": row["current_model_version"],
        "total_contributions": row["total_contributions"],
        "enrolled_at": row["enrolled_at"].isoformat() if row["enrolled_at"] else None,
    }


def submit_masked_gradient(
    connection: psycopg2.extensions.connection,
    payload: MaskedGradientUpload,
) -> dict[str, Any]:
    """
    Accept a masked gradient from a client.
    
    SecAgg Protocol:
    1. Client trains locally on their data
    2. Client computes gradients: dW = (w_t - w_t-1)
    3. Client generates random mask: R ~ N(0, sigma^2)
    4. Client sends to server: (dW + R) — the masked gradient
    5. Server receives from many clients, sums them
    6. When summed across 1000+ clients, individual masks statistically cancel
    7. Server gets: Σ(dW_i) ≈ Σ(dW_i + R_i) - Σ(R_i) ≈ 0 (if masks balanced)
    
    In practice, the "true" aggregation requires dropout or quantization to ensure
    the mathematical cancellation. Here we implement a simplified version that assumes
    proper masking on the client side.
    """
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        # Insert the masked gradient
        cursor.execute(
            """
            INSERT INTO fl_gradients (
              round_id, patient_device_id, model_version,
              masked_gradient, gradient_norm, num_local_steps
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (round_id, patient_device_id)
            DO UPDATE SET
              masked_gradient = EXCLUDED.masked_gradient,
              gradient_norm = EXCLUDED.gradient_norm,
              num_local_steps = EXCLUDED.num_local_steps,
              submitted_at = NOW()
            RETURNING id;
            """,
            (
                payload.round_id,
                payload.patient_device_id,
                payload.model_version,
                Json({"data": payload.masked_gradient}),
                payload.gradient_norm,
                payload.num_local_steps,
            ),
        )
        row = cursor.fetchone()

        if row is None:
            raise RuntimeError("Failed to insert masked gradient")

        # Update client tracking
        cursor.execute(
            """
            UPDATE fl_clients
            SET last_submission_at = NOW(),
                total_contributions = total_contributions + 1,
                updated_at = NOW()
            WHERE patient_device_id = %s;
            """,
            (payload.patient_device_id,),
        )

        # Update round submission count
        cursor.execute(
            """
            UPDATE fl_rounds
            SET clients_submitted = clients_submitted + 1,
                updated_at = NOW()
            WHERE round_id = %s;
            """,
            (payload.round_id,),
        )

    connection.commit()

    return {
        "gradient_id": str(row["id"]),
        "round_id": payload.round_id,
        "status": "received",
    }


def get_latest_model(
    connection: psycopg2.extensions.connection,
) -> dict[str, Any] | None:
    """Fetch the latest deployed FL model version."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT version, base64_weights, architecture_hash, training_round,
                   num_clients_aggregated, created_at, deployed_at
            FROM fl_model_versions
            WHERE deployed_at IS NOT NULL
            ORDER BY deployed_at DESC, version DESC
            LIMIT 1;
            """
        )
        row = cursor.fetchone()

    if row is None:
        return None

    return {
        "version": row["version"],
        "base64_weights": row["base64_weights"],
        "architecture_hash": row["architecture_hash"],
        "training_round": row["training_round"],
        "num_clients_aggregated": row["num_clients_aggregated"],
        "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        "deployed_at": row["deployed_at"].isoformat() if row["deployed_at"] else None,
    }


def get_fl_round_status(
    connection: psycopg2.extensions.connection,
    round_id: int,
) -> dict[str, Any] | None:
    """Get aggregation progress for a specific round."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT round_id, model_version, status, min_clients, clients_submitted,
                   created_at, completed_at
            FROM fl_rounds
            WHERE round_id = %s;
            """,
            (round_id,),
        )
        row = cursor.fetchone()

    if row is None:
        return None

    return {
        "round_id": row["round_id"],
        "model_version": row["model_version"],
        "status": row["status"],
        "min_clients": row["min_clients"],
        "clients_submitted": row["clients_submitted"],
        "progress_percent": min(100, int(100 * row["clients_submitted"] / max(1, row["min_clients"]))),
        "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        "completed_at": row["completed_at"].isoformat() if row["completed_at"] else None,
    }


def get_active_fl_round(
    connection: psycopg2.extensions.connection,
) -> dict[str, Any] | None:
    """Get the currently active federated learning round."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT round_id, model_version, status, min_clients, clients_submitted,
                   created_at, completed_at
            FROM fl_rounds
            WHERE status = 'active'
            ORDER BY round_id DESC
            LIMIT 1;
            """
        )
        row = cursor.fetchone()

    if row is None:
        return None

    return {
        "round_id": row["round_id"],
        "model_version": row["model_version"],
        "status": row["status"],
        "min_clients": row["min_clients"],
        "clients_submitted": row["clients_submitted"],
        "progress_percent": min(100, int(100 * row["clients_submitted"] / max(1, row["min_clients"]))),
        "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        "completed_at": row["completed_at"].isoformat() if row["completed_at"] else None,
    }


def list_active_fl_rounds(
    connection: psycopg2.extensions.connection,
) -> list[dict[str, Any]]:
    """List all currently active federated learning rounds."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT round_id, model_version, status, min_clients, clients_submitted,
                   created_at, completed_at
            FROM fl_rounds
            WHERE status = 'active'
            ORDER BY round_id DESC;
            """
        )
        rows = cursor.fetchall()

    return [
        {
            "round_id": row["round_id"],
            "model_version": row["model_version"],
            "status": row["status"],
            "min_clients": row["min_clients"],
            "clients_submitted": row["clients_submitted"],
            "progress_percent": min(100, int(100 * row["clients_submitted"] / max(1, row["min_clients"]))),
            "created_at": row["created_at"].isoformat() if row["created_at"] else None,
            "completed_at": row["completed_at"].isoformat() if row["completed_at"] else None,
        }
        for row in rows
    ]


def assign_client_to_fl_round(
    connection: psycopg2.extensions.connection,
    patient_device_id: str,
    app_version: str | None = None,
    assignment_ttl_hours: int = 24,
) -> dict[str, Any] | None:
    """
    Assign a client to an active round using weighted rendezvous hashing.

    Strategy:
    1. Reuse a non-expired cached assignment when possible.
    2. Otherwise score each active round deterministically for this client.
    3. Apply a light load penalty to reduce hot-spotting.
    4. Persist the selected assignment for a TTL window.
    """
    normalized_device_id = patient_device_id.strip()
    if not normalized_device_id:
        raise ValueError("patient_device_id must be non-empty")

    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT
              c.assigned_round_id,
              c.assignment_expires_at,
              r.round_id,
              r.model_version,
              r.status,
              r.min_clients,
              r.clients_submitted,
              r.created_at,
              r.completed_at
            FROM fl_clients c
            LEFT JOIN fl_rounds r ON r.round_id = c.assigned_round_id
            WHERE c.patient_device_id = %s;
            """,
            (normalized_device_id,),
        )
        cached = cursor.fetchone()

    now = datetime.now(timezone.utc)
    if (
        cached
        and cached.get("round_id") is not None
        and cached.get("status") == "active"
        and cached.get("assignment_expires_at")
        and cached["assignment_expires_at"] > now
    ):
        return {
            "round_id": cached["round_id"],
            "model_version": cached["model_version"],
            "status": cached["status"],
            "min_clients": cached["min_clients"],
            "clients_submitted": cached["clients_submitted"],
            "progress_percent": min(
                100,
                int(100 * cached["clients_submitted"] / max(1, cached["min_clients"])),
            ),
            "created_at": cached["created_at"].isoformat() if cached["created_at"] else None,
            "completed_at": cached["completed_at"].isoformat() if cached["completed_at"] else None,
            "assignment_source": "cached",
            "assignment_expires_at": cached["assignment_expires_at"].isoformat(),
            "assignment_policy": {
                "strategy": "weighted_rendezvous_hashing",
                "active_round_count": 1,
                "load_penalty": 0.0,
            },
        }

    rounds = list_active_fl_rounds(connection)
    if not rounds:
        return None

    def _score_round(round_status: dict[str, Any]) -> tuple[float, float]:
        round_id = int(round_status["round_id"])
        model_version = int(round_status["model_version"])
        min_clients = max(1, int(round_status["min_clients"]))
        clients_submitted = int(round_status["clients_submitted"])

        digest = hashlib.sha256(
            f"{normalized_device_id}:{round_id}:{model_version}".encode("utf-8")
        ).digest()
        base = int.from_bytes(digest[:8], byteorder="big", signed=False) / float(2**64 - 1)

        load_ratio = clients_submitted / float(min_clients)
        load_penalty = min(0.45, load_ratio * 0.20)
        return (base - load_penalty, load_penalty)

    scored = [
        (round_status, *_score_round(round_status))
        for round_status in rounds
    ]
    scored.sort(key=lambda item: item[1], reverse=True)
    selected_round = scored[0][0]
    selected_penalty = scored[0][2]

    assignment_expires_at = now + timedelta(hours=max(1, assignment_ttl_hours))
    resolved_app_version = (app_version or "").strip() or "unknown"

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO fl_clients (
              patient_device_id,
              app_version,
              current_model_version,
              assigned_round_id,
              assignment_expires_at,
              updated_at
            )
            VALUES (%s, %s, %s, %s, %s, NOW())
            ON CONFLICT (patient_device_id)
            DO UPDATE SET
              app_version = CASE
                WHEN EXCLUDED.app_version <> '' THEN EXCLUDED.app_version
                ELSE fl_clients.app_version
              END,
              current_model_version = GREATEST(fl_clients.current_model_version, EXCLUDED.current_model_version),
              assigned_round_id = EXCLUDED.assigned_round_id,
              assignment_expires_at = EXCLUDED.assignment_expires_at,
              updated_at = NOW();
            """,
            (
                normalized_device_id,
                resolved_app_version,
                int(selected_round["model_version"]),
                int(selected_round["round_id"]),
                assignment_expires_at,
            ),
        )

    connection.commit()

    return {
        **selected_round,
        "assignment_source": "rendezvous",
        "assignment_expires_at": assignment_expires_at.isoformat(),
        "assignment_policy": {
            "strategy": "weighted_rendezvous_hashing",
            "active_round_count": len(rounds),
            "load_penalty": round(selected_penalty, 6),
        },
    }


def create_fl_round(
    connection: psycopg2.extensions.connection,
    round_id: int,
    model_version: int,
    min_clients: int = 100,
) -> dict[str, Any]:
    """Create a new federated learning round."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            INSERT INTO fl_rounds (round_id, model_version, min_clients, status)
            VALUES (%s, %s, %s, 'active')
            ON CONFLICT (round_id) DO NOTHING
            RETURNING round_id, model_version, status, created_at;
            """,
            (round_id, model_version, min_clients),
        )
        row = cursor.fetchone()

    connection.commit()

    if row is None:
        raise RuntimeError(f"Failed to create FL round {round_id}")

    return {
        "round_id": row["round_id"],
        "model_version": row["model_version"],
        "status": row["status"],
        "created_at": row["created_at"].isoformat() if row["created_at"] else None,
    }


def aggregate_masked_gradients(
    connection: psycopg2.extensions.connection,
    round_id: int,
) -> dict[str, Any]:
    """
    Aggregate masked gradients from all clients in a round.
    
    Algorithm:
    1. Fetch all masked gradients for round
    2. Average them: aggregated = Σ(masked_gradient_i) / N
    3. Compute convergence metrics (norms, variance)
    4. Prepare for model update
    
    Security: Server CANNOT recover individual client gradients because:
    - Each gradient is masked: (dW_i + R_i)
    - Individual masks R_i are random and private
    - Only when summed across 1000+ clients do they cancel: Σ(R_i) ≈ 0
    """
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        # Fetch all gradients for this round
        cursor.execute(
            """
            SELECT masked_gradient, gradient_norm, patient_device_id
            FROM fl_gradients
            WHERE round_id = %s
            ORDER BY submitted_at ASC;
            """,
            (round_id,),
        )
        gradients = cursor.fetchall()

        if not gradients:
            raise ValueError(f"No gradients found for round {round_id}")

        # Extract gradient vectors and compute aggregation
        num_clients = len(gradients)
        if num_clients == 0:
            raise ValueError("No gradients to aggregate")

        # Parse gradient data
        gradient_vectors = []
        gradient_norms = []
        
        for row in gradients:
            try:
                # Extract gradient from JSONB
                grad_data = row["masked_gradient"]
                if isinstance(grad_data, dict):
                    grad_vector = grad_data.get("data", [])
                else:
                    grad_vector = grad_data
                
                gradient_vectors.append(grad_vector)
                gradient_norms.append(row["gradient_norm"] or 0.0)
            except (KeyError, ValueError) as e:
                logger.warning(f"Failed to parse gradient from {row['patient_device_id']}: {e}")
                continue

        if not gradient_vectors:
            raise ValueError("No valid gradients to aggregate")

        # Compute aggregated gradient (element-wise average)
        vector_size = len(gradient_vectors[0])
        aggregated_gradient = []
        
        for i in range(vector_size):
            total = sum(grad[i] for grad in gradient_vectors if i < len(grad))
            avg = total / num_clients
            aggregated_gradient.append(avg)

        # Compute convergence metrics
        avg_gradient_norm = sum(gradient_norms) / num_clients
        max_gradient_norm = max(gradient_norms) if gradient_norms else 0.0
        
        # Compute variance of gradient norms (convergence indicator)
        if num_clients > 1:
            variance = sum((n - avg_gradient_norm) ** 2 for n in gradient_norms) / (num_clients - 1)
            std_dev = variance ** 0.5
        else:
            std_dev = 0.0

        # Store convergence metrics
        cursor.execute(
            """
            INSERT INTO fl_convergence_metrics (round_id, metric_name, metric_value)
            VALUES (%s, %s, %s), (%s, %s, %s), (%s, %s, %s);
            """,
            (
                round_id, "avg_gradient_norm", float(avg_gradient_norm),
                round_id, "max_gradient_norm", float(max_gradient_norm),
                round_id, "gradient_std_dev", float(std_dev),
            ),
        )

        # Store aggregated result for model update
        cursor.execute(
            """
            INSERT INTO fl_gradients (
              round_id, patient_device_id, model_version,
              masked_gradient, gradient_norm, num_local_steps
            )
            VALUES (%s, %s, 0, %s, %s, 0)
            ON CONFLICT (round_id, patient_device_id) DO NOTHING;
            """,
            (
                round_id,
                "aggregated",
                Json({"data": aggregated_gradient, "aggregated": True}),
                float(avg_gradient_norm),
            ),
        )

    connection.commit()
    logger.info(f"[FL] Aggregated gradients: round={round_id}, clients={num_clients}, "
                f"avg_norm={avg_gradient_norm:.4f}, std_dev={std_dev:.4f}")

    return {
        "round_id": round_id,
        "num_clients": num_clients,
        "avg_gradient_norm": float(avg_gradient_norm),
        "max_gradient_norm": float(max_gradient_norm),
        "std_dev": float(std_dev),
        "aggregated_gradient_size": len(aggregated_gradient),
    }


def get_convergence_metrics(
    connection: psycopg2.extensions.connection,
    round_id: int,
) -> dict[str, Any]:
    """Retrieve convergence metrics for a specific round."""
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT metric_name, metric_value, recorded_at
            FROM fl_convergence_metrics
            WHERE round_id = %s
            ORDER BY recorded_at ASC;
            """,
            (round_id,),
        )
        metrics = cursor.fetchall()

    if not metrics:
        return {
            "round_id": round_id,
            "metrics": {},
            "status": "no_data"
        }

    # Group metrics by name
    metrics_dict = {}
    for row in metrics:
        name = row["metric_name"]
        if name not in metrics_dict:
            metrics_dict[name] = []
        metrics_dict[name].append(float(row["metric_value"]))

    return {
        "round_id": round_id,
        "metrics": {
            name: {
                "values": values,
                "latest": values[-1] if values else None,
                "trend": "improving" if len(values) > 1 and values[-1] < values[-2] else
                        "stable" if len(values) <= 1 else "diverging"
            }
            for name, values in metrics_dict.items()
        },
        "status": "recorded"
    }


def complete_fl_round(
    connection: psycopg2.extensions.connection,
    round_id: int,
) -> dict[str, Any]:
    """
    Mark a round as completed and prepare for next round.
    
    This happens after:
    1. Sufficient clients have submitted gradients
    2. Aggregation is complete
    3. Global model has been updated
    """
    with connection.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            UPDATE fl_rounds
            SET status = 'completed', completed_at = NOW(), updated_at = NOW()
            WHERE round_id = %s
            RETURNING round_id, model_version, clients_submitted, completed_at;
            """,
            (round_id,),
        )
        row = cursor.fetchone()

    connection.commit()

    if row is None:
        raise ValueError(f"Round {round_id} not found")

    logger.info(f"[FL] Round completed: round_id={round_id}, "
                f"model_version={row['model_version']}, "
                f"clients={row['clients_submitted']}")

    return {
        "round_id": row["round_id"],
        "model_version": row["model_version"],
        "clients_submitted": row["clients_submitted"],
        "completed_at": row["completed_at"].isoformat() if row["completed_at"] else None,
    }
