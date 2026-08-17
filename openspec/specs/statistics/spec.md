# Statistics

## Purpose

TBD

## Requirements

### Requirement: Personal consumption statistics
The system SHALL provide an authenticated user with personal aggregate statistics covering: total entries logged, total volume consumed (ml), total standard drinks, average drinks per day (over the last 30 days), and a breakdown by day of the week (average drinks per weekday). Statistics SHALL be computed over the user's full history unless a date range is specified.

#### Scenario: Personal stats retrieved
- **WHEN** an authenticated client sends a GET request to `/statistics/me`
- **THEN** the system returns HTTP 200 with an object containing `totalEntries`, `totalVolumeMl`, `totalStandardDrinks`, `avgDrinksPerDay`, and `byDayOfWeek` (array of 7 entries, Mon–Sun)

#### Scenario: Date-range scoped personal stats
- **WHEN** an authenticated client sends a GET request to `/statistics/me?from=2025-01-01&to=2025-03-31`
- **THEN** the system returns statistics computed only over entries within the specified date range

#### Scenario: Unauthenticated request rejected
- **WHEN** a client sends a GET request to `/statistics/me` without a valid Bearer token
- **THEN** the system returns HTTP 401

### Requirement: Personal consumption trend
The system SHALL return a time-series of daily standard drink totals for the authenticated user over a requested period (default: last 30 days, maximum: 365 days). This enables the frontend to render a trend chart.

#### Scenario: Trend data retrieved
- **WHEN** an authenticated client sends a GET request to `/statistics/me/trend`
- **THEN** the system returns HTTP 200 with a `data` array of objects, each containing `date` (ISO 8601 date) and `standardDrinks` (decimal), covering the last 30 days including days with zero consumption

#### Scenario: Custom period trend
- **WHEN** an authenticated client sends a GET request to `/statistics/me/trend?days=90`
- **THEN** the system returns 90 daily data points, with `standardDrinks: 0` for days with no entries

#### Scenario: Period exceeding maximum capped
- **WHEN** an authenticated client requests a trend with `days=500`
- **THEN** the system returns HTTP 400 indicating the maximum period is 365 days

### Requirement: Anonymised global statistics
The system SHALL expose an authenticated endpoint returning anonymised, aggregated statistics across all users: total number of users with at least one entry, overall average standard drinks per user per day (last 30 days), and the most popular beer names (top 5 by entry count). No per-user data SHALL be included in this response.

#### Scenario: Global stats retrieved
- **WHEN** an authenticated client sends a GET request to `/statistics/global`
- **THEN** the system returns HTTP 200 with `activeUsers`, `globalAvgDrinksPerDay`, and `topBeerNames` (array of up to 5 name strings)

#### Scenario: Global stats hide individual data
- **WHEN** a client inspects the `/statistics/global` response
- **THEN** the response contains no user IDs, emails, or any other PII

### Requirement: Statistics cache refresh
The system SHALL refresh its cached aggregate data from the `beer-tracking-service` internal API on a configurable schedule (default: every 15 minutes). The endpoint response SHALL include a `cachedAt` timestamp indicating when the underlying data was last refreshed.

#### Scenario: Cache timestamp included in response
- **WHEN** any statistics endpoint returns a 200 response
- **THEN** the response body includes a `cachedAt` ISO 8601 datetime field

#### Scenario: Stale cache serves data without error
- **WHEN** the most recent cache refresh failed but data from a previous refresh exists
- **THEN** the system returns the stale cached data with HTTP 200, including the `cachedAt` timestamp of the last successful refresh
