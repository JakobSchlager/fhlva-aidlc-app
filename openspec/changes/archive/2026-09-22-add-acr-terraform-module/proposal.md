## Why

No Azure Container Registry exists for this project: `infra/terraform/stages/dev/main.tf` has `acr_id = ""` as a placeholder, so the `kubelet_acr_pull` role assignment is never created and the AKS kubelet identity cannot pull images. This blocks Helm deployment of all application workloads and is the direct blocker for completing task 4.4 of the `aks-cni-overlay-migration` change.

## What Changes

- **Add** a new `infra/terraform/modules/acr/` Terraform module that provisions an Azure Container Registry with admin access disabled and the geo-redundancy and SKU appropriate for the environment
- **Update** `infra/terraform/stages/dev/main.tf` to call the ACR module and replace the empty `acr_id = ""` local with the module's resource ID output, making the `kubelet_acr_pull` role assignment active
- **Add** the ACR login server as an output in `infra/terraform/stages/dev/outputs.tf` so deploy scripts can discover it without hardcoding

## Capabilities

### New Capabilities

- `terraform-acr`: Terraform module that creates and configures an Azure Container Registry, including naming conventions, SKU, tags, and outputs (resource ID, login server)

### Modified Capabilities

- `terraform-stage-dev`: The dev stage requirement "Dev stage calls all root modules" must be extended to include the `acr` module alongside `network`, `aks`, and `keyvault`

## Impact

- `infra/terraform/modules/acr/` — new directory with `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`
- `infra/terraform/stages/dev/main.tf` — add `module "acr"` block, replace `local.acr_id` placeholder with `module.acr.acr_id`
- `infra/terraform/stages/dev/outputs.tf` — add `acr_login_server` output
- `openspec/specs/terraform-stage-dev/spec.md` — update module list requirement to include `acr`
