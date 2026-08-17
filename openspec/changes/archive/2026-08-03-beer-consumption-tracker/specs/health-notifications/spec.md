## ADDED Requirements

### Requirement: Configurable consumption thresholds
The system SHALL maintain per-installation configurable thresholds for daily and weekly standard drink limits. Default values SHALL be 2 standard drinks per day and 14 per week (aligned with WHO low-risk guidelines). Thresholds SHALL be settable via environment variables (`THRESHOLD_DAILY_DRINKS`, `THRESHOLD_WEEKLY_DRINKS`).

#### Scenario: Defaults applied when environment variables are absent
- **WHEN** the service starts without `THRESHOLD_DAILY_DRINKS` or `THRESHOLD_WEEKLY_DRINKS` set
- **THEN** the service uses 2 daily and 14 weekly as the active thresholds

#### Scenario: Custom thresholds applied from environment
- **WHEN** the service starts with `THRESHOLD_DAILY_DRINKS=3` and `THRESHOLD_WEEKLY_DRINKS=20`
- **THEN** the service evaluates all warnings against 3 and 20 respectively

### Requirement: Scheduled consumption evaluation
The system SHALL query the `beer-tracking-service` internal summary endpoint every 5 minutes for all registered users. If a user's consumption exceeds the daily or weekly threshold, the system SHALL create or update a warning record for that user. If consumption drops back below the threshold (e.g., after a new day/week begins), the system SHALL mark any existing warnings as resolved.

#### Scenario: Daily threshold exceeded — warning created
- **WHEN** the scheduled evaluation runs and a user's total standard drinks today exceed the daily threshold
- **THEN** the system creates a warning record with `type: "DAILY_EXCEEDED"`, `userId`, `triggeredAt`, and `status: "ACTIVE"` if one does not already exist for today

#### Scenario: Weekly threshold exceeded — warning created
- **WHEN** the scheduled evaluation runs and a user's total standard drinks this week exceed the weekly threshold
- **THEN** the system creates a warning record with `type: "WEEKLY_EXCEEDED"` and `status: "ACTIVE"` if one does not already exist for this week

#### Scenario: Consumption falls below threshold — warning resolved
- **WHEN** the scheduled evaluation runs and no threshold is exceeded for a user who has an existing `ACTIVE` warning (e.g., due to week rollover)
- **THEN** the system sets the warning's `status` to `"RESOLVED"` and records `resolvedAt`

### Requirement: Retrieve active warnings for a user
The system SHALL allow an authenticated user to retrieve their own active (unresolved) warnings.

#### Scenario: Active warnings returned
- **WHEN** an authenticated client sends a GET request to `/notifications/warnings?status=ACTIVE`
- **THEN** the system returns HTTP 200 with a list of active warning objects for the authenticated user, including `type`, `triggeredAt`, and `threshold`

#### Scenario: No active warnings returns empty list
- **WHEN** an authenticated client sends a GET request to `/notifications/warnings?status=ACTIVE` and the user has no active warnings
- **THEN** the system returns HTTP 200 with an empty `items` array

#### Scenario: Unauthenticated request rejected
- **WHEN** a client sends a GET request to `/notifications/warnings` without a valid Bearer token
- **THEN** the system returns HTTP 401

### Requirement: Acknowledge a warning
The system SHALL allow an authenticated user to acknowledge an active warning. Acknowledgement SHALL set the warning's `status` to `"ACKNOWLEDGED"` and record `acknowledgedAt`. Acknowledged warnings SHALL remain visible in history but not appear in active-only queries.

#### Scenario: Successful acknowledgement
- **WHEN** an authenticated client sends a POST request to `/notifications/warnings/{id}/acknowledge` for one of their own active warnings
- **THEN** the system sets `status: "ACKNOWLEDGED"`, records `acknowledgedAt`, and returns HTTP 200 with the updated warning

#### Scenario: Acknowledge another user's warning rejected
- **WHEN** an authenticated client sends a POST request to `/notifications/warnings/{id}/acknowledge` for a warning belonging to a different user
- **THEN** the system returns HTTP 403
