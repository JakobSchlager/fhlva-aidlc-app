## ADDED Requirements

### Requirement: Helm charts deploy to minikube without Azure dependencies
The system SHALL deploy the full umbrella Helm chart to a local minikube cluster without requiring Azure credentials, an Azure Key Vault, the Secrets Store CSI driver, or an Azure Container Registry.

#### Scenario: Helm install succeeds on clean minikube
- **WHEN** `helm upgrade --install beer-tracker ./charts/beer-tracker -f values-minikube.yaml --namespace beer-tracker --create-namespace` is run against a minikube cluster
- **THEN** the release is installed without errors, and all CRDs (`SecretProviderClass`) are not applied in local mode

#### Scenario: All pods reach Running state
- **WHEN** the Helm release is installed with `values-minikube.yaml`
- **THEN** all five application pods reach `Running` state within 5 minutes and pass liveness/readiness probes

### Requirement: secretsProvider flag controls CSI vs plain-secret path
Each Helm sub-chart SHALL support a `secretsProvider` value accepting `azure` (default) or `local`. When set to `local`, the deployment MUST omit the CSI volume and volume mount, and the `SecretProviderClass` resource MUST NOT be rendered.

#### Scenario: local mode skips CSI volume
- **WHEN** `secretsProvider: local` is set
- **THEN** the rendered deployment manifest contains no `csi` volume block and no `secrets-store` volume mount

#### Scenario: azure mode renders CSI volume
- **WHEN** `secretsProvider: azure` is set (or omitted, using default)
- **THEN** the rendered deployment manifest contains the `secrets-store.csi.k8s.io` volume and corresponding volume mount, unchanged from current behaviour

### Requirement: Plain Kubernetes Secrets provide secret values in local mode
When `secretsProvider: local`, all secrets (database passwords, RSA private key, internal API key) SHALL be provided via pre-existing Kubernetes `Secret` objects whose names match the pattern `<release>-<chart>-secrets`, so that existing `secretKeyRef` and `AUTH_PRIVATE_KEY_PATH` environment variable references in the deployment templates resolve correctly.

#### Scenario: Secret values available to pods
- **WHEN** Kubernetes Secrets are created before `helm install` and `secretsProvider: local` is set
- **THEN** all pods can read their required environment variables and file mounts without errors

#### Scenario: Missing Kubernetes Secret
- **WHEN** a required Kubernetes Secret is absent and `secretsProvider: local` is set
- **THEN** the pod enters `Pending` or `CrashLoopBackOff` with a Kubernetes event clearly indicating the missing secret

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
The system SHALL provide `scripts/deploy-minikube.sh` that automates: enabling the ingress addon, activating the minikube Docker environment, building all images, creating Kubernetes Secrets from `.env`, running `helm dependency update`, and running `helm upgrade --install` with `values-minikube.yaml`.

#### Scenario: Script is idempotent
- **WHEN** `scripts/deploy-minikube.sh` is run a second time without changes
- **THEN** it completes without errors and the cluster state is unchanged

#### Scenario: Script fails on missing minikube
- **WHEN** `scripts/deploy-minikube.sh` is run on a machine where minikube is not installed or not started
- **THEN** the script exits with a non-zero code and an informative error message
