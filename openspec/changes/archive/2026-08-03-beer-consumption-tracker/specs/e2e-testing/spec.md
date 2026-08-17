## ADDED Requirements

### Requirement: Test suite reachability guard
The E2E test suite SHALL verify that the application stack at `http://localhost:8080` is reachable before any test runs. If the stack is not reachable, the suite SHALL fail immediately with a clear message instructing the developer to start the stack with `podman compose up`.

#### Scenario: Stack not running at test start
- **WHEN** the Playwright global setup runs and `http://localhost:8080` returns a connection error
- **THEN** the suite exits with a non-zero code and prints "Stack unreachable — run podman compose up before running E2E tests"

#### Scenario: Stack running at test start
- **WHEN** the Playwright global setup runs and `http://localhost:8080` responds with HTTP 200
- **THEN** the suite proceeds to execute all test files

### Requirement: Authenticated test fixture
The E2E suite SHALL provide a `loggedInPage` fixture that handles user registration and login on behalf of individual tests. Each fixture invocation SHALL create a unique test user (`test-<uuid>@example.com`) so tests are isolated and do not share state. The fixture SHALL expose an authenticated Playwright `Page` object ready for use.

#### Scenario: Fixture creates isolated test user
- **WHEN** a test requests the `loggedInPage` fixture
- **THEN** a unique email address is generated, a new user is registered via `POST /auth/register`, and the fixture logs in via the UI login form, resulting in a `Page` that shows the authenticated dashboard

#### Scenario: Fixture login failure surfaces clearly
- **WHEN** the registration or login step within the fixture fails
- **THEN** the fixture throws a descriptive error identifying which step failed before the test body runs

### Requirement: Authentication journey tests
The system SHALL have E2E tests verifying the registration and login flows accessible at `http://localhost:8080`.

#### Scenario: Successful registration redirects to dashboard
- **WHEN** a user navigates to `/register`, fills in a valid email and password (≥ 8 chars), and submits the form
- **THEN** the page redirects to the dashboard and the dashboard heading is visible

#### Scenario: Duplicate email shows error
- **WHEN** a user attempts to register with an email address already in use
- **THEN** an error message is visible on the registration page and no redirect occurs

#### Scenario: Short password shows validation error
- **WHEN** a user submits the registration form with a password shorter than 8 characters
- **THEN** a validation error message referencing the password constraint is visible

#### Scenario: Valid login reaches dashboard
- **WHEN** a registered user navigates to `/login`, enters correct credentials, and submits
- **THEN** the page redirects to the dashboard

#### Scenario: Wrong password shows error
- **WHEN** a user submits the login form with an incorrect password
- **THEN** an error message is visible and no redirect occurs

### Requirement: Dashboard content tests
The system SHALL have E2E tests verifying that the dashboard renders meaningful content and that beer entry submission works end-to-end.

#### Scenario: Dashboard renders stat tiles
- **WHEN** an authenticated user navigates to the dashboard
- **THEN** at least one stat tile element is visible and the page does not show a blank or empty body

#### Scenario: Beer entry form is visible
- **WHEN** an authenticated user views the dashboard
- **THEN** the beer entry form with fields for beer name, volume, and ABV is visible

#### Scenario: Submitting a beer entry appears in history
- **WHEN** an authenticated user submits a valid beer entry via the dashboard form
- **THEN** navigating to the history page shows a row containing the submitted beer name

### Requirement: History page tests
The system SHALL have E2E tests verifying pagination, filtering, editing, and deletion of consumption history entries.

#### Scenario: History page loads entries
- **WHEN** an authenticated user with at least one entry navigates to `/history`
- **THEN** the history table is visible and contains at least one row

#### Scenario: Date-range filter narrows results
- **WHEN** a user sets a date range that excludes all existing entries and applies the filter
- **THEN** the history table shows zero rows or an empty-state message

#### Scenario: Edit entry updates displayed value
- **WHEN** a user clicks the edit button on an entry, changes the beer name, and saves
- **THEN** the updated beer name appears in the history table row

#### Scenario: Delete entry removes row
- **WHEN** a user clicks the delete button on an entry and confirms the deletion
- **THEN** the row is no longer present in the history table

### Requirement: Notifications panel tests
The system SHALL have E2E tests verifying that the notifications panel renders and that warning acknowledgement works.

#### Scenario: Notifications panel renders on dashboard
- **WHEN** an authenticated user views the dashboard
- **THEN** the notifications panel element is present in the DOM (even if no active warnings exist)

#### Scenario: Acknowledging a warning removes its banner
- **WHEN** an ACTIVE warning banner is visible in the notifications panel and the user clicks its Acknowledge button
- **THEN** the banner is no longer visible after the action completes

### Requirement: Statistics page tests
The system SHALL have E2E tests verifying that the personal statistics and global statistics pages render charts and key data without errors.

#### Scenario: Personal stats page renders charts
- **WHEN** an authenticated user navigates to `/stats`
- **THEN** both the day-of-week bar chart and the trend line chart are visible with no error state shown

#### Scenario: Personal stats page shows cachedAt
- **WHEN** an authenticated user views the statistics page
- **THEN** a "last updated" or `cachedAt` timestamp is visible on the page

#### Scenario: Global stats page renders key metrics
- **WHEN** an authenticated user navigates to `/global`
- **THEN** the page displays values for active users, global average drinks per day, and the top beer names list

#### Scenario: Global stats page shows cachedAt
- **WHEN** an authenticated user views the global statistics page
- **THEN** a `cachedAt` timestamp is visible on the page
