# Beer Tracking

## Purpose

TBD

## Requirements

### Requirement: Log a beer consumption entry
The system SHALL allow an authenticated user to record a beer consumption entry. Each entry SHALL capture: beer name (string, required), volume in millilitres (integer, required, >0), ABV percentage (decimal 0–100, required), and an optional timestamp (ISO 8601; defaults to server-side `now()` if omitted). The entry SHALL be associated with the authenticated user's ID from the JWT.

#### Scenario: Successful entry creation
- **WHEN** an authenticated client sends a POST request to `/tracking/entries` with valid beer name, volume, and ABV fields
- **THEN** the system persists the entry, returns HTTP 201, and returns the full entry object including generated `id` and `timestamp`

#### Scenario: Unauthenticated request rejected
- **WHEN** a client sends a POST request to `/tracking/entries` without a valid Bearer token
- **THEN** the system returns HTTP 401

#### Scenario: Invalid volume rejected
- **WHEN** an authenticated client sends a POST request to `/tracking/entries` with `volume` set to 0 or a negative number
- **THEN** the system returns HTTP 400 with a validation error on the `volume` field

### Requirement: Retrieve personal consumption history
The system SHALL allow an authenticated user to retrieve their own consumption entries, paginated, with optional date-range filters (`from` and `to` query parameters in ISO 8601 date format).

#### Scenario: Retrieve recent entries
- **WHEN** an authenticated client sends a GET request to `/tracking/entries`
- **THEN** the system returns HTTP 200 with a paginated list of the user's entries, newest first, with `page`, `pageSize`, and `totalCount` metadata

#### Scenario: Date-range filter applied
- **WHEN** an authenticated client sends a GET request to `/tracking/entries?from=2025-01-01&to=2025-01-31`
- **THEN** the system returns only entries with timestamps within the specified range (inclusive)

#### Scenario: Empty result for no entries
- **WHEN** an authenticated client with no consumption history sends a GET request to `/tracking/entries`
- **THEN** the system returns HTTP 200 with an empty `items` array and `totalCount: 0`

### Requirement: Update a consumption entry
The system SHALL allow an authenticated user to update any field of one of their own entries. The system SHALL reject update attempts targeting another user's entry.

#### Scenario: Successful update
- **WHEN** an authenticated client sends a PUT request to `/tracking/entries/{id}` with valid updated fields for an entry they own
- **THEN** the system updates the entry and returns HTTP 200 with the updated entry object

#### Scenario: Update another user's entry rejected
- **WHEN** an authenticated client sends a PUT request to `/tracking/entries/{id}` for an entry belonging to a different user
- **THEN** the system returns HTTP 403

#### Scenario: Entry not found
- **WHEN** an authenticated client sends a PUT request to `/tracking/entries/{id}` where `id` does not exist
- **THEN** the system returns HTTP 404

### Requirement: Delete a consumption entry
The system SHALL allow an authenticated user to permanently delete one of their own entries.

#### Scenario: Successful deletion
- **WHEN** an authenticated client sends a DELETE request to `/tracking/entries/{id}` for an entry they own
- **THEN** the system removes the entry and returns HTTP 204

#### Scenario: Delete another user's entry rejected
- **WHEN** an authenticated client sends a DELETE request to `/tracking/entries/{id}` for an entry belonging to a different user
- **THEN** the system returns HTTP 403

### Requirement: Internal summary endpoint for other services
The system SHALL expose an internal REST endpoint that returns the total standard drinks consumed by a given user within a specified time window. This endpoint SHALL only be accessible with a valid internal service API key header and SHALL NOT be exposed through the public API gateway.

#### Scenario: Internal summary retrieved
- **WHEN** an internal service sends a GET request to `/internal/tracking/summary?userId={id}&from={date}&to={date}` with a valid `X-Internal-Key` header
- **THEN** the system returns HTTP 200 with `{ "userId": "...", "totalVolumeMl": ..., "totalStandardDrinks": ... }` for the given window

#### Scenario: Missing internal key rejected
- **WHEN** a request is received at the internal endpoint without the `X-Internal-Key` header
- **THEN** the system returns HTTP 401
