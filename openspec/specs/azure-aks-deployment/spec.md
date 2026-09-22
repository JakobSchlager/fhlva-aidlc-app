## Purpose

End-to-end deployment of the Beer Tracker application to Azure Kubernetes Service using Terraform for infrastructure provisioning and Helm for application deployment. Covers infrastructure setup, image build/push, cluster access, and CI/CD integration.

## Requirements

### Requirement: Terraform provisions all required Azure resources
The system SHALL deploy all Azure infrastructure via `infra/terraform/stages/dev/` using `terraform apply`, producing a fully functional AKS cluster, ACR, VNet, Application Gateway, and supporting role assignments.

The resource group and Log Analytics workspace are prerequisites that Terraform reads as data sources but does not create; they must exist before `terraform apply` is run.

#### Scenario: Fresh environment deployment
- **WHEN** `terraform init && terraform plan -out=tfplan && terraform apply tfplan` is run inside `infra/terraform/stages/dev/`
- **THEN** all modules complete without errors and the outputs (`aks_cluster_name`, `acr_login_server`, `ingress_public_ip`) are available

#### Scenario: Idempotent re-apply
- **WHEN** `terraform apply` is re-run after a successful deployment with no configuration changes
- **THEN** Terraform reports zero changes and exits without modifying any resource

### Requirement: Container images built and pushed to ACR before Helm deployment
The system SHALL build container images for all five services and push them to ACR, tagged with the current git commit SHA, before the Helm release is applied.

#### Scenario: Images pushed with commit SHA tag
- **WHEN** ACR login succeeds and images are built and pushed for each service
- **THEN** each image is available in ACR at `<acrLoginServer>/<service>:<sha>` and the Helm deployment can pull them

#### Scenario: ACR pull authorised from AKS
- **WHEN** the AKS kubelet identity has the `AcrPull` role on ACR (granted via Terraform role assignment)
- **THEN** AKS nodes pull images from ACR without explicit imagePullSecrets

### Requirement: Helm deployment uses Azure values without Key Vault references
The system SHALL provide `values-azure.yaml` containing Azure-specific Helm values (ingress class). The deploy script SHALL NOT pass Key Vault names, tenant IDs, or workload identity client IDs to `helm upgrade --install`. Pods SHALL read secrets from `beer-tracker-secrets` via `envFrom`.

#### Scenario: Helm release succeeds with Azure values
- **WHEN** `helm upgrade --install beer-tracker ./charts/beer-tracker -f values-azure.yaml --set ...` is run
- **THEN** the release installs without errors and all pods start, reading secrets from the `beer-tracker-secrets` Kubernetes Secret via `envFrom`

#### Scenario: Pods do not use CSI volumes or Workload Identity annotations
- **WHEN** a running Beer Tracker pod spec is inspected
- **THEN** it SHALL NOT contain SecretProviderClass volume references, CSI driver volume mounts, or `azure.workload.identity/client-id` annotations

### Requirement: deploy-azure.sh automates the full deployment sequence
The system SHALL provide `scripts/deploy-azure.sh` that automates: reading ACR login server and AKS cluster name from `terraform output`, logging in to ACR using `--expose-token` (compatible with both Docker and Podman), installing Bitnami PostgreSQL in-cluster, initialising the four application databases from `postgres-init/init.sql`, creating or updating `beer-tracker-secrets`, building and pushing all five images, and running `helm upgrade --install` with all required values. The script SHALL be idempotent.

#### Scenario: End-to-end deployment from script
- **WHEN** `scripts/deploy-azure.sh` is executed with `AZURE_RESOURCE_GROUP`, `POSTGRES_APP_PASSWORD`, `INTERNAL_API_KEY`, and `AUTH_RSA_KEY_PATH` set
- **THEN** the full stack is deployed to Azure without manual intervention between steps

#### Scenario: Script is safe to re-run
- **WHEN** `scripts/deploy-azure.sh` is run against a cluster that already has a running Beer Tracker deployment
- **THEN** it upgrades the release in place without re-initialising databases or duplicating resources

### Requirement: AKS cluster administrative access requires Entra ID authentication
The AKS cluster SHALL be configured with Microsoft Entra ID managed integration and Azure RBAC so that all access to the Kubernetes API server is authenticated via Entra ID. Local Kubernetes accounts SHALL be disabled to eliminate static certificate-based cluster-admin credentials.

#### Scenario: Local accounts are disabled
- **WHEN** `az aks get-credentials --admin` is attempted against the cluster
- **THEN** the command fails because local admin credentials are disabled

#### Scenario: Human operator accesses the cluster
- **WHEN** an operator with the `Azure Kubernetes Service RBAC Cluster Admin` role runs `az aks get-credentials` and issues a kubectl command
- **THEN** they are authenticated via Entra ID (interactive or device-code flow) before the API server accepts the request

#### Scenario: CI/CD service principal accesses the cluster
- **WHEN** the GitHub Actions service principal holds the `Azure Kubernetes Service RBAC Cluster Admin` role on the AKS resource and runs `az aks get-credentials`
- **THEN** it receives a kubeconfig that authenticates via its service principal token, not a static cluster certificate

### Requirement: GitHub Actions secrets required for CI/CD pipeline
The system SHALL document all GitHub Actions secrets required by the CI/CD pipeline and how to obtain each value. Required secrets are: `AZURE_CREDENTIALS` (service principal JSON), `AZURE_RESOURCE_GROUP`, `POSTGRES_APP_PASSWORD`, `INTERNAL_API_KEY`, and `AUTH_RSA_PRIVATE_KEY` (PEM content). ACR login server and AKS cluster name are read from `terraform output` at deploy time and do not need to be stored as secrets.

#### Scenario: CI/CD runs without manual intervention after secrets are set
- **WHEN** all required GitHub Actions secrets are configured and a push is made to `main`
- **THEN** the CI/CD pipeline builds images, pushes to ACR, deploys via Helm, and completes without operator input
