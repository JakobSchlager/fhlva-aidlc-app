## Why

The project currently uses Bicep for Azure infrastructure, but Terraform is required for future infrastructure instrumentation to align with broader platform tooling standards. As a first step, we migrate the core cluster infrastructure — networking, AKS, and Key Vault — to Terraform, establishing the module structure that all future components (PostgreSQL, ACR, monitoring) will follow.

## What Changes

- **New**: `infra/terraform/` directory with a root module and three child modules
- **New**: `modules/network` — VNet, subnets (AKS, AppGW, Postgres), Application Gateway, NSG with configurable ingress IP allowlist
- **New**: `modules/aks` — AKS cluster with Azure CNI, AGIC addon, Container Insights, Secrets Store CSI, Workload Identity/OIDC, and a configurable API server IP allowlist
- **New**: `modules/keyvault` — Key Vault (RBAC mode), one User-Assigned Managed Identity per service, federated credentials for AKS Workload Identity, and six application secrets
- **New**: Root module wiring — cross-module role assignments (AGIC → AppGW Contributor, kubelet → ACR AcrPull placeholder), Azure Storage remote state backend
- **New**: Per-environment variable files (`dev.tfvars`, `staging.tfvars`) for non-secret configuration
- Existing Bicep files in `infra/` remain unchanged during this migration phase

## Capabilities

### New Capabilities

- `terraform-network`: VNet + subnet topology and Application Gateway provisioning, with NSG-enforced ingress IP allowlisting
- `terraform-aks`: AKS cluster lifecycle management including node pool autoscaling, add-on configuration, and API server access control via authorized IP ranges
- `terraform-keyvault`: Key Vault provisioning, per-service managed identity creation, AKS Workload Identity federated credential binding, and secret storage

### Modified Capabilities

<!-- No existing spec-level requirements are changing — this is a new infrastructure delivery mechanism for the same application topology. -->

## Impact

- **Infrastructure**: New `infra/terraform/` tree; existing `infra/*.bicep` files are untouched
- **CI/CD**: Pipeline will need a new `terraform init / plan / apply` stage targeting `infra/terraform/`; Azure Storage account for remote state must be provisioned as a bootstrap prerequisite
- **Secrets**: Six application secrets move from Bicep `@secure()` parameters to Terraform `sensitive` variables; injection mechanism (CI/CD environment variables or `secrets.auto.tfvars`) must be established
- **Dependencies**: Requires `hashicorp/azurerm` ~> 4.x and `hashicorp/azuread` ~> 3.x providers
