## Purpose

End-to-end deployment of the Beer Tracker application to Azure Kubernetes Service using Bicep for infrastructure provisioning and Helm for application deployment. Covers infrastructure setup, image build/push, cluster access, and CI/CD integration.

## Requirements

### Requirement: Bicep templates provision all required Azure resources
The system SHALL deploy all Azure infrastructure via `infra/main.bicep` using a single `az deployment group create` command, producing a fully functional AKS cluster, ACR, Key Vault (with secrets), PostgreSQL Flexible Server, VNet, Application Gateway, and Log Analytics workspace.

#### Scenario: Fresh resource group deployment
- **WHEN** `az deployment group create --template-file infra/main.bicep --parameters infra/main.bicepparam` is run with all `@secure()` parameters supplied
- **THEN** all seven resource modules complete without errors and the deployment outputs (`acrLoginServer`, `aksClusterName`, `keyVaultName`, `postgresFqdn`, `ingressPublicIp`, `serviceIdentityClientIds`) are available

#### Scenario: Idempotent re-deployment
- **WHEN** the same Bicep deployment command is re-run after a successful deployment
- **THEN** ARM incremental mode applies only changed resources and the deployment succeeds without data loss

### Requirement: Container images built and pushed to ACR before Helm deployment
The system SHALL build Docker images for all five services and push them to ACR, tagged with the current git commit SHA, before the Helm release is applied.

#### Scenario: Images pushed with commit SHA tag
- **WHEN** `az acr login` succeeds and `docker build` + `docker push` are run for each service
- **THEN** each image is available in ACR at `<acrLoginServer>/<service>:<sha>` and the Helm deployment can pull them

#### Scenario: ACR pull authorised from AKS
- **WHEN** the AKS kubelet identity has the `AcrPull` role on ACR (wired by Bicep)
- **THEN** AKS nodes pull images from ACR without explicit imagePullSecrets

### Requirement: Helm deployment uses Azure values without Key Vault references
The system SHALL provide `values-azure.yaml` containing Azure-specific Helm values (ingress class). The deploy script SHALL NOT pass `keyVaultName`, `tenantId`, or per-service `clientId` values to `helm upgrade --install`. Pods SHALL read secrets from `beer-tracker-secrets` via `envFrom`.

#### Scenario: Helm release succeeds with Azure values
- **WHEN** `helm upgrade --install beer-tracker ./charts/beer-tracker -f values-azure.yaml --set ...` is run
- **THEN** the release installs without errors and all pods start, reading secrets from the `beer-tracker-secrets` Kubernetes Secret via `envFrom`

#### Scenario: Pods do not use CSI volumes or Workload Identity annotations
- **WHEN** a running Beer Tracker pod spec is inspected
- **THEN** it SHALL NOT contain SecretProviderClass volume references, CSI driver volume mounts, or `azure.workload.identity/client-id` annotations

### Requirement: deploy-azure.sh automates the full deployment sequence
The system SHALL provide `scripts/deploy-azure.sh` that automates: creating the resource group (if absent), running the Bicep deployment, capturing outputs, logging in to ACR, building and pushing images, getting AKS credentials, running `helm dependency update`, and running `helm upgrade --install` with all required values. The script SHALL be idempotent.

#### Scenario: End-to-end deployment from script
- **WHEN** `scripts/deploy-azure.sh` is executed with required environment variables set (passwords, API key, RSA key path)
- **THEN** the full stack is deployed to Azure without manual intervention between steps

#### Scenario: Script skips resource group creation if it exists
- **WHEN** the target resource group already exists
- **THEN** `az group create` completes idempotently without error

### Requirement: PostgreSQL schema initialised after first deployment
The system SHALL document the one-time manual step of running `postgres-init/init.sql` against the Azure PostgreSQL Flexible Server after the first Bicep deployment, including the connection string format and TLS requirement.

#### Scenario: Schema initialisation command documented
- **WHEN** a developer follows the README for the Azure scenario
- **THEN** they find a clear command to run `psql` against the Flexible Server with the correct hostname, user, and `sslmode=require`

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
The system SHALL document all six GitHub Actions secrets required by `.github/workflows/ci.yml` (`AZURE_CREDENTIALS`, `ACR_LOGIN_SERVER`, `AKS_CLUSTER_NAME`, `AZURE_RESOURCE_GROUP`, `KEY_VAULT_NAME`, `AZURE_TENANT_ID`) and how to obtain each value.

#### Scenario: CI/CD runs without manual intervention after secrets are set
- **WHEN** all six GitHub Actions secrets are configured and a push is made to `main`
- **THEN** the CI/CD pipeline builds images, pushes to ACR, deploys via Helm, and runs E2E tests without operator input
