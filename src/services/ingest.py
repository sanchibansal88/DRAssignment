"""PostgreSQL ingestion helpers for the frontend API."""
from __future__ import annotations

import json
import logging
import os
from http import HTTPStatus
from typing import Any, Dict, Tuple

from psycopg import conninfo, errors
from psycopg_pool import ConnectionPool

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL)
logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL environment variable is required for ingestion")
try:
    CONNINFO = conninfo.make_conninfo(DATABASE_URL)
except errors.ProgrammingError as exc:
    raise RuntimeError(
        "Invalid DATABASE_URL format. Use postgresql://user:pass@host:port/db"
    ) from exc

POOL_MIN = int(os.getenv("PG_POOL_MIN", "1"))
POOL_MAX = int(os.getenv("PG_POOL_MAX", "10"))

pool = ConnectionPool(conninfo=CONNINFO, min_size=POOL_MIN, max_size=POOL_MAX)


def init_schema() -> None:
    """Ensure the table exists before processing traffic."""
    with pool.connection() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS user_profiles (
                user_id TEXT PRIMARY KEY,
                full_name TEXT,
                email TEXT,
                email_hash TEXT,
                metadata JSONB,
                request_id TEXT,
                ingest_ts BIGINT
            )
            """
        )
        conn.commit()


def ingest_user(payload: Dict[str, Any]) -> Tuple[Dict[str, Any], HTTPStatus]:
    required = ["user_id", "email", "request_id", "ingest_ts"]
    missing = [field for field in required if field not in payload]
    if missing:
        return {
            "error": f"missing fields: {', '.join(missing)}"
        }, HTTPStatus.BAD_REQUEST

    try:
        with pool.connection() as conn:
            conn.execute(
                """
                INSERT INTO user_profiles (user_id, full_name, email, email_hash, metadata, request_id, ingest_ts)
                VALUES (%(user_id)s, %(full_name)s, %(email)s, %(email_hash)s, %(metadata)s::jsonb, %(request_id)s, %(ingest_ts)s)
                ON CONFLICT (user_id)
                DO UPDATE SET
                    full_name = EXCLUDED.full_name,
                    email = EXCLUDED.email,
                    email_hash = EXCLUDED.email_hash,
                    metadata = EXCLUDED.metadata,
                    request_id = EXCLUDED.request_id,
                    ingest_ts = EXCLUDED.ingest_ts
                """,
                {
                    **payload,
                    "metadata": json.dumps(payload.get("metadata", {})),
                },
            )
            conn.commit()
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("failed to persist user %s", payload.get("user_id"))
        return {
            "error": "database write failed",
            "detail": str(exc),
        }, HTTPStatus.INTERNAL_SERVER_ERROR

    return {
        "status": "stored",
        "user_id": payload["user_id"],
        "request_id": payload["request_id"],
    }, HTTPStatus.CREATED
