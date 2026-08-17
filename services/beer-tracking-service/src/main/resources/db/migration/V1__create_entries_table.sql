CREATE TABLE entries (
    id          UUID         NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id     UUID         NOT NULL,
    beer_name   VARCHAR(255) NOT NULL,
    volume_ml   INT          NOT NULL,
    abv         DECIMAL(5,2) NOT NULL,
    timestamp   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_entries_user_id  ON entries (user_id);
CREATE INDEX idx_entries_timestamp ON entries (timestamp);
