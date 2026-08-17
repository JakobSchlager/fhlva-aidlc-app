-- Statistics cache tables for statistics-service
-- All timestamps stored as TIMESTAMPTZ (UTC)

-- Personal aggregate stats cache (one row per user)
CREATE TABLE personal_stats_cache (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID UNIQUE NOT NULL,
    total_entries           INT,
    total_volume_ml         BIGINT,
    total_standard_drinks   DECIMAL(10, 2),
    avg_drinks_per_day_30d  DECIMAL(5, 2),
    by_day_of_week          JSONB,           -- [{dayName, avgDrinks}, ...] Mon–Sun
    cached_at               TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_personal_stats_cache_user_id ON personal_stats_cache (user_id);

-- Global (anonymised) stats cache (latest row is the current snapshot)
CREATE TABLE global_stats_cache (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    active_users             INT,
    global_avg_drinks_per_day DECIMAL(5, 2),
    top_beer_names           JSONB,           -- ["BeerA", "BeerB", ...]
    cached_at                TIMESTAMPTZ NOT NULL
);

-- Daily trend cache (one row per user per day)
CREATE TABLE daily_trend_cache (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    trend_date      DATE NOT NULL,
    standard_drinks DECIMAL(5, 2),
    UNIQUE (user_id, trend_date)
);

CREATE INDEX idx_daily_trend_cache_user_date ON daily_trend_cache (user_id, trend_date);
