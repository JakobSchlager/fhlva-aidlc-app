## ADDED Requirements

### Requirement: User registration
The system SHALL allow a new user to register with a unique email address and a password. The password SHALL be stored as a bcrypt hash and never in plain text. The system SHALL reject registration if the email address is already in use and SHALL return a descriptive error.

#### Scenario: Successful registration
- **WHEN** a client sends a POST request to `/auth/register` with a valid email and password (minimum 8 characters)
- **THEN** the system creates a new user record, returns HTTP 201, and returns the new user's `id` and `email` (no password or hash)

#### Scenario: Duplicate email rejected
- **WHEN** a client sends a POST request to `/auth/register` with an email address that already exists
- **THEN** the system returns HTTP 409 with an error body indicating the email is already registered

#### Scenario: Weak password rejected
- **WHEN** a client sends a POST request to `/auth/register` with a password shorter than 8 characters
- **THEN** the system returns HTTP 400 with a validation error listing the password constraint

### Requirement: User login and JWT issuance
The system SHALL authenticate a user by email and password and, upon success, issue a signed JWT (RS256) containing the user's `sub` (user ID), `email`, and `exp` (15-minute expiry). The system SHALL also issue a longer-lived refresh token (7-day expiry) stored server-side and returned in an `HttpOnly` cookie.

#### Scenario: Successful login
- **WHEN** a client sends a POST request to `/auth/login` with correct email and password
- **THEN** the system returns HTTP 200 with a JSON body containing `accessToken` and sets a `refreshToken` `HttpOnly` cookie

#### Scenario: Invalid credentials rejected
- **WHEN** a client sends a POST request to `/auth/login` with an incorrect password or unknown email
- **THEN** the system returns HTTP 401 with a generic "invalid credentials" message (no detail on which field is wrong)

### Requirement: Token refresh
The system SHALL allow clients to obtain a new access token by presenting a valid, unexpired refresh token cookie. The old refresh token SHALL be invalidated (rotated) on use.

#### Scenario: Successful token refresh
- **WHEN** a client sends a POST request to `/auth/refresh` with a valid `HttpOnly` refresh token cookie
- **THEN** the system returns HTTP 200 with a new `accessToken` and sets a new `refreshToken` cookie, invalidating the old one

#### Scenario: Expired or revoked refresh token rejected
- **WHEN** a client sends a POST request to `/auth/refresh` with an expired or already-used refresh token
- **THEN** the system returns HTTP 401 and clears the refresh token cookie

### Requirement: Logout
The system SHALL allow a user to log out, which SHALL revoke the current refresh token server-side and clear the cookie.

#### Scenario: Successful logout
- **WHEN** a client sends a POST request to `/auth/logout` with a valid refresh token cookie
- **THEN** the system revokes the refresh token, clears the `refreshToken` cookie, and returns HTTP 204

### Requirement: JWT public key endpoint
The system SHALL expose a public endpoint that returns the RS256 public key in JWK Set format so that other services can validate access tokens without calling auth-service per request.

#### Scenario: Public key retrieval
- **WHEN** any client sends a GET request to `/auth/.well-known/jwks.json`
- **THEN** the system returns HTTP 200 with the JWKS document (no authentication required)
