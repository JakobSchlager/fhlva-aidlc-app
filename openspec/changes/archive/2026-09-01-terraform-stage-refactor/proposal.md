## Why

The current Terraform root requires seven `TF_VAR_*` environment variables and explicit `-backend-config` flags on every `terraform init`, making local usage and CI pipelines fragile and dependent on manual secret injection. Separating infrastructure configuration into per-environment stage folders and removing Terraform's ownership of secret values eliminates this ceremony.

## What Changes

- **New**: `infra/terraform/stages/dev/` — self-contained Terraform root for the dev environment; all non-secret config as `locals`, fully-specified backend, zero env vars required
- **New**: `infra/terraform/stages/staging/` — same shape for staging, with its own subscription ID and state key
- **New**: `scripts/set-keyvault-secrets.sh` — bootstrap script to populate Key Vault secret values via `az keyvault secret set`; accepts `--environment` flag
- **Modified**: `infra/terraform/modules/keyvault` — removes the 6 sensitive variable declarations and the 6 `azurerm_key_vault_secret` resources; retains Key Vault, UAMIs, role assignments, and federated credentials
- **BREAKING**: Root-level flat files removed (`main.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `providers.tf`, `backend.tf`, `dev.tfvars`, `staging.tfvars`)
- **Updated**: `infra/terraform/README.md` — reflects new workflow

## Capabilities

### New Capabilities

- `terraform-stage-dev`: Stage folder for the dev environment — self-contained Terraform root with hardcoded locals, fully-specified backend, no variables file
- `terraform-stage-staging`: Stage folder for the staging environment — same shape as dev with staging-specific values
- `keyvault-secret-bootstrap`: Script-based secret population replacing Terraform-managed secret values

### Modified Capabilities

- `terraform-keyvault`: Key Vault module no longer accepts or stores secret values; responsibility for secret content moves to the bootstrap script

## Impact

- `infra/terraform/modules/keyvault/` — variables.tf and main.tf change (secret vars and resources removed)
- `infra/terraform/stages/` — new directory tree (two new Terraform roots)
- `scripts/set-keyvault-secrets.sh` — new file
- `infra/terraform/README.md` — updated workflow docs
- CI/CD pipelines — must update `terraform init` and `apply` invocations to target `stages/dev` or `stages/staging`; secret injection moves to a separate pipeline step using the bootstrap script
