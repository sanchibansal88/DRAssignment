"""Business logic helpers used by the frontend API."""
from __future__ import annotations

import hashlib
import time
import uuid
from typing import Any, Dict


def process_user(payload: Dict[str, Any], request_id: str) -> Dict[str, Any]:
    """Normalize and enrich the incoming user payload."""
    first_name = payload.get("first_name")
    last_name = payload.get("last_name")
    full_name = payload.get("name")

    if first_name or last_name:
        full_name = " ".join(part for part in [first_name, last_name] if part)

    email = (payload.get("email") or "").strip().lower()
    user_id = payload.get("user_id") or str(uuid.uuid4())

    enriched = {
        "user_id": user_id,
        "full_name": full_name,
        "email": email,
        "metadata": payload.get("metadata", {}),
        "request_id": request_id,
        "ingest_ts": int(time.time()),
    }

    # Deterministic hash used for deduplication downstream.
    enriched["email_hash"] = hashlib.sha256(email.encode()).hexdigest()
    return enriched
