-- Schema for the user_profiles table used by the frontend API ingestion helpers.
CREATE TABLE IF NOT EXISTS user_profiles (
    user_id TEXT PRIMARY KEY,
    full_name TEXT,
    email TEXT,
    email_hash TEXT,
    metadata JSONB,
    request_id TEXT,
    ingest_ts BIGINT
);
