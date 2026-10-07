## Purpose

Local Kubernetes deployment of the Beer Tracker application to a minikube cluster using Helm. Covers Azure-agnostic chart configuration, secrets management via the shared `beer-tracker-secrets` Kubernetes Secret (same as Azure), image building into minikube, ingress setup, in-cluster PostgreSQL, and the deploy script.

## Requirements

### Requirement: Helm charts deploy to minikube without Azure dependencies
The system SHALL deploy the full umbrella Helm chart to a local minikube cluster without requiring Azure credentials, an Azure Key Vault, the Secrets Store CSI driver, or an Azure Container Registry.

#### Scenario: Helm install succeeds on clean minikube
- **WHEN** `helm upgrade --install beer-tracker ./charts/beer-tracker -f values-minikube.yaml --namespace beer-tracker --create-namespace` is run against a minikube cluster
- **THEN** the release is installed without errors, and no Azure-specific resources (such as `SecretProviderClass`) are rendered

#### Scenario: All pods reach Running state
- **WHEN** the Helm release is installed with `values-minikube.yaml`
- **THEN** all five application pods reach `Running` state within 5 minutes and pass liveness/readiness probes

### Requirement: Images built into minikube's Docker daemon
The system SHALL document and script the process of building all five service images directly into minikube's Docker daemon using `eval $(minikube docker-env)`, and `values-minikube.yaml` SHALL set `imagePullPolicy: Never` for all services.

#### Scenario: Image available without a registry
- **WHEN** images are built with the minikube Docker environment active and `imagePullPolicy: Never` is set
- **THEN** pods start without attempting to pull from any external registry

#### Scenario: Stale image
- **WHEN** source code changes and the image is rebuilt with the minikube Docker environment active
- **THEN** restarting the deployment (`kubectl rollout restart`) picks up the new image

### Requirement: nginx ingress routes all services
The system SHALL configure `values-minikube.yaml` with `ingress.class: nginx` and SHALL document enabling the minikube ingress addon (`minikube addons enable ingress`), so the ingress resource routes traffic correctly using the nginx ingress controller.

#### Scenario: Ingress routes frontend
- **WHEN** a request reaches the minikube IP on port 80 at path `/`
- **THEN** it is routed to the frontend service

#### Scenario: Ingress routes API services
- **WHEN** a request reaches the minikube IP at paths `/auth/...`, `/tracking/...`, `/notifications/...`, `/statistics/...`
- **THEN** it is routed to the corresponding backend service

### Requirement: PostgreSQL runs as a pod in the cluster
The system SHALL provide a PostgreSQL deployment (or instruct use of the Bitnami PostgreSQL Helm chart) in the `beer-tracker` namespace so services can connect to the database without depending on a compose stack running in parallel.

#### Scenario: Services connect to in-cluster Postgres
- **WHEN** PostgreSQL is deployed in the same namespace and services are configured with the cluster-internal hostname
- **THEN** all services establish database connections successfully

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
