-- V2: Scheduler concurrency is handled via PostgreSQL advisory locks (pg_try_advisory_lock).
-- No additional table is required; this migration is intentionally a no-op placeholder.
SELECT 1;
