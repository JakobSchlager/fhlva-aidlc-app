## ADDED Requirements

### Requirement: Compose stack starts with a single command
The system SHALL provide a compose file that starts all five application containers and a PostgreSQL container with a single `podman compose up -d` (or `docker compose up -d`) command, with no manual pre-steps beyond creating a `.env` file from `.env.example`.

#### Scenario: First-time startup
- **WHEN** a developer copies `.env.example` to `.env`, fills in values, and runs `podman compose up -d`
- **THEN** all six containers (auth-service, beer-tracking-service, health-notification-service, statistics-service, frontend, postgres) start and become healthy within 5 minutes

#### Scenario: Service restarts on failure
- **WHEN** a container exits unexpectedly
- **THEN** the compose runtime restarts it automatically (`restart: unless-stopped`)

### Requirement: Secrets injected via .env file
The system SHALL inject all service secrets (database passwords, RSA private key path, internal API key) through environment variables sourced from a `.env` file, not hardcoded in the compose file.

#### Scenario: Missing .env file
- **WHEN** `podman compose up` is run without a `.env` file present
- **THEN** compose exits with a clear error indicating missing required variables

#### Scenario: .env.example committed to source control
- **WHEN** a developer clones the repository
- **THEN** a `.env.example` file exists with all required variable names and placeholder values, but no real secrets

### Requirement: PostgreSQL initialised on first start
The system SHALL automatically execute the schema initialisation SQL (`postgres-init/init.sql`) when the PostgreSQL container is first created, so all service databases and users exist before application containers attempt to connect.

#### Scenario: Fresh volume start
- **WHEN** the postgres container starts with no existing data volume
- **THEN** all databases (`auth_db`, `tracking_db`, `notifications_db`, `statistics_db`) and their respective service users are created automatically

#### Scenario: Existing volume restart
- **WHEN** the postgres container restarts with an existing data volume
- **THEN** the init SQL is not re-executed and existing data is preserved

### Requirement: nginx routes all services through a single port
The system SHALL expose a single nginx reverse proxy on `localhost:8080` that routes traffic to all services by path prefix (`/auth`, `/tracking`, `/notifications`, `/statistics`, `/`), matching the routing behaviour of the Kubernetes ingress.

#### Scenario: Frontend accessible
- **WHEN** a browser navigates to `http://localhost:8080/`
- **THEN** the frontend is served

#### Scenario: API routing
- **WHEN** a request is sent to `http://localhost:8080/auth/...`
- **THEN** it is forwarded to the auth-service container on port 8081

### Requirement: RSA private key mounted as a file
The system SHALL mount the RSA private key PEM file into the auth-service container at the path the service expects (`/run/secrets/auth-rs256-private-key.pem` or as configured), using a compose volume bind-mount from the local `secrets/` directory.

#### Scenario: Key file present
- **WHEN** `secrets/auth-rs256-private-key.pem` exists and the stack starts
- **THEN** the auth-service reads the key from the mounted path and signs JWTs successfully

#### Scenario: Key file missing
- **WHEN** `secrets/auth-rs256-private-key.pem` does not exist and the stack starts
- **THEN** the auth-service container fails to start with a clear error about the missing key file

### Requirement: Podman Compose compatibility confirmed
The system SHALL document any incompatibilities between the compose file and Podman Compose ≥ 1.0, and resolve them without breaking Docker Compose compatibility.

#### Scenario: Run with Podman Compose
- **WHEN** `podman compose up -d` is executed on a machine with Podman Compose ≥ 1.0 installed
- **THEN** all containers start without errors related to compose file syntax or network configuration

#### Scenario: Run with Docker Compose
- **WHEN** `docker compose up -d` is executed on a machine with Docker Compose v2 installed
- **THEN** all containers start without errors
