## Why

Azure Key Vault introduces significant infrastructure and operational complexity (a Terraform module with 17+ resources, a manual bootstrap script, CSI Driver SecretProviderClass manifests, and Workload Identity pod annotations) for managing six static application secrets that change infrequently. Replacing it with a native Kubernetes Secret removes this entire layer, reduces Terraform surface area, eliminates the runtime Azure dependency, and makes local dev environments (Minikube/Compose) work without mocking.

## What Changes

- **Remove** the `modules/keyvault` Terraform module (Key Vault resource, 4 UAMIs, 4 federated identity credentials, 4 role assignments, 6 placeholder secret slots)
- **Remove** `scripts/set-keyvault-secrets.sh` bootstrap script
- **Remove** Helm SecretProviderClass manifests and CSI volume mounts from all four service charts
- **Remove** Workload Identity annotations from all pod specs
- **Remove** `keyVaultName`, `tenantId`, and per-service `clientId` Helm values
- **Add** a single Kubernetes Secret `beer-tracker-secrets` in the `beer-tracker` namespace holding all six secrets
- **Add** manual bootstrap script: `scripts/set-k8s-secrets.sh` prompts for values and creates/updates the K8s secret directly
- **Modify** `scripts/deploy-azure.sh` to create `beer-tracker-secrets` from env vars before invoking Helm, and to remove KV-related output capture and `--set` flags
- **Modify** pod specs to consume secrets via `envFrom` referencing `beer-tracker-secrets`

## Capabilities

### New Capabilities

- `kubernetes-secrets-bootstrap`: Specification for how the `beer-tracker-secrets` Kubernetes Secret is created, populated, and consumed — covering the manual operator path (`scripts/set-k8s-secrets.sh`) and the deploy-script path (`deploy-azure.sh`)

### Modified Capabilities

- `terraform-keyvault`: The keyvault Terraform module is removed entirely; this spec is retired
- `keyvault-secret-bootstrap`: Replaced by `kubernetes-secrets-bootstrap`; this spec is retired
- `azure-aks-deployment`: Helm deploy steps and deploy script no longer reference Key Vault, Workload Identity, or CSI Driver; pods now use `envFrom` for secrets
- `deployment-documentation`: Operator runbook and prerequisite steps updated to reflect the new manual bootstrap script and removal of KV setup steps

## Impact

- **Terraform**: `modules/keyvault/` directory removed; stage modules (`stages/dev/`, `stages/staging/`) drop the keyvault module call and its outputs
- **Helm charts**: SecretProviderClass resources removed; pod specs gain `envFrom`; values files drop KV-related keys
- **Scripts**: `set-keyvault-secrets.sh` removed; `set-k8s-secrets.sh` added; `deploy-azure.sh` updated
- **GitHub Actions**: Not applicable — the CI/CD workflow (`ci.yml`) has been removed from the repository
- **AKS cluster**: Secrets Store CSI Driver addon no longer required (can be disabled); Workload Identity is no longer needed for secret access (can be disabled if no other use)
- **Local dev**: No change to Compose or Minikube setup; secrets already injected differently there
