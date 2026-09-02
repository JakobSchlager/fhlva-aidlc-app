## ADDED Requirements

### Requirement: A single Kubernetes Secret holds all six application secrets
The system SHALL maintain one Kubernetes Secret named `beer-tracker-secrets` in the `beer-tracker` namespace containing all six application secret keys: `auth-rs256-private-key`, `auth-db-password`, `tracking-db-password`, `notifications-db-password`, `statistics-db-password`, and `internal-api-key`. No other Kubernetes Secret or volume mount SHALL be used to deliver these secrets to pods.

#### Scenario: Secret exists with all required keys before Helm deploy
- **WHEN** `kubectl get secret beer-tracker-secrets -n beer-tracker -o json` is run after bootstrap
- **THEN** the secret SHALL exist and contain all six keys with non-empty, non-placeholder values

#### Scenario: Pods consume secrets via envFrom
- **WHEN** a Beer Tracker pod spec is inspected
- **THEN** it SHALL declare `envFrom: - secretRef: name: beer-tracker-secrets` and SHALL NOT declare CSI volumes, SecretProviderClass references, or Workload Identity annotations for secret access

### Requirement: deploy-azure.sh creates the secret before Helm deploy
`scripts/deploy-azure.sh` SHALL create or update `beer-tracker-secrets` using `kubectl create secret generic` with `--from-literal` flags sourced from environment variables, before running `helm upgrade --install`. The step SHALL be idempotent, using `--dry-run=client -o yaml | kubectl apply -f -` or equivalent.

#### Scenario: Deploy script creates the secret on first run
- **WHEN** `scripts/deploy-azure.sh` runs and `beer-tracker-secrets` does not yet exist
- **THEN** the `kubectl` step SHALL create `beer-tracker-secrets` with all six keys populated from the script's environment variables

#### Scenario: Deploy script updates the secret if it already exists
- **WHEN** `scripts/deploy-azure.sh` runs and `beer-tracker-secrets` already exists
- **THEN** the `kubectl` step SHALL succeed and update the secret without error

#### Scenario: Helm upgrade follows secret creation
- **WHEN** `scripts/deploy-azure.sh` runs
- **THEN** the secret creation step SHALL complete before `helm upgrade --install` is invoked

### Requirement: Manual path via set-k8s-secrets.sh creates the secret
The repository SHALL provide `scripts/set-k8s-secrets.sh` that accepts an `--environment` flag (values: `dev`, `staging`), gets AKS credentials for the target cluster, and creates or updates `beer-tracker-secrets` by prompting the operator for each secret value interactively. The script SHALL be idempotent.

#### Scenario: Script accepts --environment flag
- **WHEN** `scripts/set-k8s-secrets.sh --environment dev` is run
- **THEN** it SHALL target the dev AKS cluster, prompt for all six secret values, and create or update `beer-tracker-secrets` in the `beer-tracker` namespace

#### Scenario: Script rejects unknown environments
- **WHEN** `scripts/set-k8s-secrets.sh --environment unknown` is run
- **THEN** it SHALL exit with a non-zero status and print a usage error

#### Scenario: Script is idempotent
- **WHEN** `scripts/set-k8s-secrets.sh` is run a second time for the same environment
- **THEN** it SHALL succeed without errors and update all six secret values in the existing secret

#### Scenario: Script documents prerequisites
- **WHEN** a user reads the script file or runs it with `--help`
- **THEN** prerequisites (Azure CLI logged in, kubectl installed, AKS cluster provisioned), the `--environment` flag, and example invocations SHALL be visible
