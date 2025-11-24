import csv
import io
import json
import os
import uuid
from datetime import datetime
from http import HTTPStatus

from azure.storage.blob import BlobServiceClient
from flask import Flask, jsonify, request

from business_logic import process_user
from ingest import ingest_user, init_schema

app = Flask(__name__)

try:
    init_schema()
except Exception as exc:  # pylint: disable=broad-except
    app.logger.warning("schema init failed during import: %s", exc)


SERVICE_MODE = os.getenv("SERVICE_MODE", "active").strip().lower()
READ_ONLY_MODES = {"readonly", "read-only"}
CSV_SOURCE_PATH = os.getenv("CSV_SOURCE_PATH", "sample_users.csv")
STORAGE_ACCOUNT_NAME = os.getenv("STORAGE_ACCOUNT_NAME")
STORAGE_ACCOUNT_KEY = os.getenv("STORAGE_ACCOUNT_KEY")
STORAGE_CONTAINER_NAME = os.getenv("STORAGE_CONTAINER_NAME")
STORAGE_BLOB_NAME = os.getenv("STORAGE_BLOB_NAME")


def _error(message: str, status: HTTPStatus = HTTPStatus.BAD_REQUEST):
    return jsonify({"error": message}), status


def _resolve_csv_rows():
    if all(
        [
            STORAGE_ACCOUNT_NAME,
            STORAGE_ACCOUNT_KEY,
            STORAGE_CONTAINER_NAME,
            STORAGE_BLOB_NAME,
        ]
    ):
        account_url = f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
        blob_client = BlobServiceClient(
            account_url=account_url, credential=STORAGE_ACCOUNT_KEY
        ).get_blob_client(
            container=STORAGE_CONTAINER_NAME, blob=STORAGE_BLOB_NAME
        )
        payload = blob_client.download_blob().content_as_text()
        return list(csv.DictReader(io.StringIO(payload)))

    path = CSV_SOURCE_PATH
    if not os.path.isabs(path):
        path = os.path.join(os.path.dirname(__file__), path)
    with open(path, "r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def _metadata_from_row(raw_value):
    if not raw_value:
        return {}
    if isinstance(raw_value, dict):
        return raw_value.copy()
    try:
        return json.loads(raw_value)
    except json.JSONDecodeError:
        return {"raw_metadata": raw_value}


@app.route("/healthz", methods=["GET"])
def healthz():
    # health check passes if schema init + quick ingest noop works
    status, http_status = ingest_user(
        {
            "user_id": "healthcheck",
            "full_name": "health check",
            "email": "health@example.com",
            "email_hash": "skip",
            "metadata": {},
            "request_id": "health",
            "ingest_ts": 0,
        }
    )
    if http_status >= HTTPStatus.INTERNAL_SERVER_ERROR:
        return jsonify(status), HTTPStatus.SERVICE_UNAVAILABLE
    return jsonify({"status": "ok"})


@app.route("/users", methods=["POST"])
def create_user():
    if SERVICE_MODE in READ_ONLY_MODES:
        return _error(
            "writes are temporarily disabled during failover",
            HTTPStatus.SERVICE_UNAVAILABLE,
        )

    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return _error("JSON body required")

    name = payload.get("name")
    email = payload.get("email")
    if not name or not email:
        return _error("name and email are required fields")

    request_id = str(uuid.uuid4())
    envelope = {"request_id": request_id, "user": payload}

    enriched = process_user(payload, request_id)

    body, status = ingest_user(enriched)
    body.setdefault("request_id", request_id)
    return jsonify(body), status


@app.route("/users/import", methods=["POST"])
def import_users():
    if SERVICE_MODE in READ_ONLY_MODES:
        return _error(
            "writes are temporarily disabled during failover",
            HTTPStatus.SERVICE_UNAVAILABLE,
        )

    body_json = request.get_json(silent=True) or {}
    start_row = body_json.get("start_id")
    try:
        start_row = int(start_row) if start_row is not None else 0
    except (TypeError, ValueError):
        return _error("start_id must be an integer", HTTPStatus.BAD_REQUEST)
    if start_row < 0:
        return _error("start_id must be >= 0", HTTPStatus.BAD_REQUEST)

    try:
        rows = _resolve_csv_rows()
    except FileNotFoundError:
        return _error("CSV source file not found", HTTPStatus.NOT_FOUND)
    except Exception as exc:  # pylint: disable=broad-except
        app.logger.exception("failed to load csv rows: %s", exc)
        return _error("failed to load csv data", HTTPStatus.INTERNAL_SERVER_ERROR)

    if start_row > 0:
        if start_row > len(rows):
            return _error("start_id exceeds available rows", HTTPStatus.BAD_REQUEST)
        rows = rows[start_row - 1 :]

    imported = []
    errors = []
    for row in rows:
        metadata = _metadata_from_row(row.get("metadata"))
        metadata["csv_imported_at"] = datetime.utcnow().isoformat()
        payload = {
            "user_id": row.get("user_id"),
            "name": row.get("full_name") or row.get("name"),
            "email": row.get("email"),
            "metadata": metadata,
        }
        if not payload["email"]:
            errors.append({"user_id": payload["user_id"], "error": "missing email"})
            continue

        request_id = str(uuid.uuid4())
        enriched = process_user(payload, request_id)
        body, status = ingest_user(enriched)
        if status >= HTTPStatus.BAD_REQUEST:
            errors.append(
                {
                    "user_id": payload["user_id"],
                    "error": body.get("error", "ingest failed"),
                }
            )
            continue
        imported.append(body["user_id"])

    response = {"imported": imported, "errors": errors}
    status_code = HTTPStatus.OK if not errors else HTTPStatus.MULTI_STATUS
    return jsonify(response), status_code


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
