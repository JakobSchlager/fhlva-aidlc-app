-- V1: Create warnings table for health notifications

CREATE TABLE IF NOT EXISTS warnings (
    id               UUID         NOT NULL DEFAULT gen_random_uuid(),
    user_id          UUID         NOT NULL,
    type             VARCHAR(50)  NOT NULL,
    status           VARCHAR(50)  NOT NULL DEFAULT 'ACTIVE',
    triggered_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    resolved_at      TIMESTAMPTZ,
    acknowledged_at  TIMESTAMPTZ,
    threshold        DECIMAL(5,2) NOT NULL,
    CONSTRAINT pk_warnings PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_warnings_user_id
    ON warnings (user_id);

CREATE INDEX IF NOT EXISTS idx_warnings_user_type_status
    ON warnings (user_id, type, status);
