## ADDED Requirements

### Requirement: Shared beer-tracker-secrets provides secret values on minikube
The minikube deployment SHALL provide all application secrets through a single Kubernetes Secret named `beer-tracker-secrets` in the `beer-tracker` namespace, with the same name and keys as the Azure deployment: `auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD` and `INTERNAL_API_KEY`. The Secret SHALL exist before `helm upgrade --install` runs. No per-service Secrets (`<release>-<chart>-secrets`) SHALL be created.

#### Scenario: Secret has the keys the charts consume
- **WHEN** `kubectl get secret beer-tracker-secrets -n beer-tracker -o json` is run after `scripts/deploy-minikube.sh`
- **THEN** the Secret exists and contains exactly the keys `auth-rs256-private-key`, `SPRING_DATASOURCE_PASSWORD` and `INTERNAL_API_KEY`, each non-empty

#### Scenario: No pod is stuck in CreateContainerConfigError
- **WHEN** the Helm release is installed after the Secret has been created
- **THEN** no Beer Tracker pod reports `CreateContainerConfigError` and each reaches `Ready`

#### Scenario: No per-service Secrets are created
- **WHEN** `kubectl get secrets -n beer-tracker` is run after `scripts/deploy-minikube.sh`
- **THEN** no Secret matching `beer-tracker-*-service-secrets` exists

### Requirement: values-minikube.yaml configures the private key path
`values-minikube.yaml` SHALL set `AUTH_PRIVATE_KEY_PATH` to `/etc/secrets/auth-rs256-private-key` for auth-service, matching `values-azure.yaml`, so the service finds the RSA key mounted from `beer-tracker-secrets`.

#### Scenario: auth-service finds its signing key
- **WHEN** auth-service starts on minikube
- **THEN** it reads the private key from `/etc/secrets/auth-rs256-private-key` and starts without a missing-key error

## MODIFIED Requirements

### Requirement: deploy-minikube.sh script automates the setup
The system SHALL provide `scripts/deploy-minikube.sh` that automates: enabling the ingress addon, building all images into minikube, creating the shared `beer-tracker-secrets` Kubernetes Secret from `.env`, installing in-cluster PostgreSQL and initialising the databases, running `helm dependency update`, and running `helm upgrade --install` with `values-minikube.yaml`. The Secret creation SHALL be idempotent and SHALL use `kubectl create secret generic --dry-run=client -o yaml | kubectl apply -f -` or equivalent.

#### Scenario: Script is idempotent
- **WHEN** `scripts/deploy-minikube.sh` is run a second time without changes
- **THEN** it completes without errors and the cluster state is unchanged

#### Scenario: Script fails on missing minikube
- **WHEN** `scripts/deploy-minikube.sh` is run on a machine where minikube is not installed or not started
- **THEN** the script exits with a non-zero code and an informative error message

#### Scenario: Secret values come from .env
- **WHEN** `scripts/deploy-minikube.sh` runs with `.env` defining `POSTGRES_PASSWORD`, `INTERNAL_API_KEY` and `AUTH_RSA_KEY_PATH`
- **THEN** `SPRING_DATASOURCE_PASSWORD` equals `POSTGRES_PASSWORD`, `INTERNAL_API_KEY` equals the `.env` value, and `auth-rs256-private-key` holds the content of the key file

## REMOVED Requirements

### Requirement: secretsProvider flag controls CSI vs plain-secret path
**Reason**: The charts no longer have CSI volumes, a `SecretProviderClass`, or a `secretsProvider` value (removed in the `k8s-native-secrets` change). The flag is dead configuration.
**Migration**: Remove `secretsProvider: local` from `values-minikube.yaml`. Secrets are delivered via `beer-tracker-secrets` on every environment.

### Requirement: Plain Kubernetes Secrets provide secret values in local mode
**Reason**: Per-service `<release>-<chart>-secrets` Secrets and `secretKeyRef` references no longer match the charts, which consume `beer-tracker-secrets` via `envFrom`.
**Migration**: See the "Shared beer-tracker-secrets provides secret values on minikube" requirement.
