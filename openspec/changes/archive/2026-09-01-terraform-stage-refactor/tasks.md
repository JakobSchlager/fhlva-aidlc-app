## 1. Update keyvault module

- [x] 1.1 Remove the 6 sensitive variable declarations from `infra/terraform/modules/keyvault/variables.tf`
- [x] 1.2 Replace the 6 `azurerm_key_vault_secret` resource `value` arguments with the static string `"PLACEHOLDER"` in `infra/terraform/modules/keyvault/main.tf`
- [x] 1.3 Verify `lifecycle { ignore_changes = [value] }` is present on all 6 secret resources

## 2. Create dev stage

- [x] 2.1 Create directory `infra/terraform/stages/dev/`
- [x] 2.2 Create `infra/terraform/stages/dev/backend.tf` with fully specified `azurerm` backend (resource group, storage account, container, key `dev/terraform.tfstate`)
- [x] 2.3 Create `infra/terraform/stages/dev/providers.tf` with `required_version`, `required_providers`, and `provider "azurerm"` block sourcing `subscription_id` from `local.subscription_id`
- [x] 2.4 Create `infra/terraform/stages/dev/main.tf` with `locals` block (dev subscription ID, project name, environment, location, allowed IPs, alert email) and module calls for `network`, `aks`, `keyvault` using `../../modules/<name>` and `local.*` references
- [x] 2.5 Create `infra/terraform/stages/dev/outputs.tf` by adapting the outputs from the old root `outputs.tf`

## 3. Create staging stage

- [x] 3.1 Create directory `infra/terraform/stages/staging/`
- [x] 3.2 Create `infra/terraform/stages/staging/backend.tf` with fully specified `azurerm` backend using key `staging/terraform.tfstate`
- [x] 3.3 Create `infra/terraform/stages/staging/providers.tf` identical in structure to dev, sourcing `local.subscription_id`
- [x] 3.4 Create `infra/terraform/stages/staging/main.tf` with staging-specific locals (staging subscription ID, environment `"staging"`) and the same module calls
- [x] 3.5 Create `infra/terraform/stages/staging/outputs.tf`

## 4. Create bootstrap script

- [x] 4.1 Create `scripts/set-keyvault-secrets.sh` with `--environment` flag parsing, usage comment block, and `az keyvault secret set` calls for all 6 secrets
- [x] 4.2 Make the script executable (`chmod +x`)
- [x] 4.3 Verify the script exits non-zero for unknown `--environment` values

## 5. Remove old flat root files

- [x] 5.1 Delete `infra/terraform/main.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `providers.tf`, `backend.tf`
- [x] 5.2 Delete `infra/terraform/dev.tfvars` and `infra/terraform/staging.tfvars`

## 6. Update documentation

- [x] 6.1 Rewrite `infra/terraform/README.md` to document the new workflow: `cd stages/dev && terraform init && terraform apply`, then `scripts/set-keyvault-secrets.sh --environment dev`
- [x] 6.2 Document backend bootstrap: the storage account must be created once before first `terraform init` (reference `scripts/bootstrap-tf-state.sh`)
- [x] 6.3 Update the module structure diagram in the README

## 7. Validation

- [x] 7.1 Run `terraform init` inside `stages/dev/` and confirm it succeeds without flags
- [x] 7.2 Run `terraform validate` inside `stages/dev/` and confirm no errors
- [x] 7.3 Run `terraform init` and `terraform validate` inside `stages/staging/`
- [x] 7.4 Confirm no `TF_VAR_*` references remain in the keyvault module
