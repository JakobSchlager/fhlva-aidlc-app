## 1. Remove Terraform Key Vault Module

- [x] 1.1 Delete `infra/terraform/modules/keyvault/` directory and all its files (`main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`)
- [x] 1.2 Remove the `module "keyvault"` call from `infra/terraform/stages/dev/main.tf`
- [x] 1.3 Remove the `module "keyvault"` call from `infra/terraform/stages/staging/main.tf`
- [x] 1.4 Remove all keyvault module output references (`key_vault_name`, `key_vault_uri`, `key_vault_id`, `*_service_client_id`) from stage `outputs.tf` files
- [x] 1.5 Run `terraform validate` in each stage directory to confirm no dangling references

## 2. Add Manual Bootstrap Script

- [x] 2.1 Create `scripts/set-k8s-secrets.sh` with `--environment dev|staging` flag, usage/help block, and interactive prompts for all six secrets
- [x] 2.2 Implement idempotent secret creation using `kubectl create secret generic beer-tracker-secrets --dry-run=client -o yaml | kubectl apply -f -`
- [x] 2.3 Delete `scripts/set-keyvault-secrets.sh`

## 3. Update Helm Charts

- [x] 3.1 Remove `SecretProviderClass` manifest(s) from the Helm chart (all services)
- [x] 3.2 Remove CSI volume and volumeMount definitions from all four service pod specs in the chart
- [x] 3.3 Remove Workload Identity pod annotations (`azure.workload.identity/client-id`) from all four service pod specs
- [x] 3.4 Add `envFrom: - secretRef: name: beer-tracker-secrets` to all four service pod specs
- [x] 3.5 Remove `keyVaultName`, `tenantId`, and per-service `clientId` keys from `values.yaml` and `values-azure.yaml`

## 4. Update Deploy Script

- [x] 4.1 Remove Key Vault output capture steps (`keyVaultName`, `tenantId`, per-service `clientId`) from `scripts/deploy-azure.sh`
- [x] 4.2 Add `kubectl create secret generic beer-tracker-secrets` step (using env vars for secret values) to `scripts/deploy-azure.sh`, before `helm upgrade --install`
- [x] 4.3 Remove `--set keyVaultName=...`, `--set tenantId=...`, and `--set *.clientId=...` flags from the `helm upgrade` invocation in `scripts/deploy-azure.sh`

## 5. Update Documentation

- [x] 5.1 Update `README.md` Azure section: replace `set-keyvault-secrets.sh` steps with `set-k8s-secrets.sh --environment <env>` steps
- [x] 5.2 Update `README.md` Azure prerequisites: remove Key Vault / Workload Identity setup; add note that `beer-tracker-secrets` must exist before first Helm deploy
- [x] 5.3 Remove the GitHub Actions secrets setup section from README (CI/CD workflow no longer exists)

> **Bicep not in scope**: `infra/*.bicep` files (including `infra/keyvault.bicep`) are NOT modified here. Bicep is being replaced by Terraform and those files will be retired as part of a separate cleanup. All infrastructure changes in this change target `infra/terraform/` only.
>
> **GitHub Actions not in scope**: The CI/CD workflow (`ci.yml`) has been removed from the repository. No workflow changes are required.

## 6. Sync Specs to Main

- [x] 6.1 Run `openspec sync --change k8s-native-secrets` to merge delta specs into `openspec/specs/`
- [x] 6.2 Verify `openspec/specs/terraform-keyvault/` and `openspec/specs/keyvault-secret-bootstrap/` are marked retired or removed
- [x] 6.3 Verify `openspec/specs/kubernetes-secrets-bootstrap/spec.md` exists with the new requirements
