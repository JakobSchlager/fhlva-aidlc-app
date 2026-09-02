## Context

The Beer Tracker application runs on Azure Kubernetes Service with a supporting stack of networking (VNet, Application Gateway), Key Vault, ACR, PostgreSQL, and Log Analytics. All of this is currently expressed as Bicep templates in `infra/`. The team needs to move to Terraform as the infrastructure tooling standard.

This first migration phase covers the three components required to stand up a functional, secured cluster: networking, AKS, and Key Vault. PostgreSQL, ACR, and monitoring follow in subsequent phases. The Bicep files remain in place and are not deleted; they serve as the reference implementation and continue to document every resource attribute.

Two access-control requirements drive several design decisions:
1. **Ingress IP allowlist** — only known public CIDRs may reach the Application Gateway (the cluster's public entry point).
2. **API server IP allowlist** — only trusted CIDRs (developer workstations, CI/CD runners) may call the Kubernetes API server.

## Goals / Non-Goals

**Goals:**
- Establish the `infra/terraform/` tree with a root module and three child modules (`network`, `aks`, `keyvault`)
- Reproduce the resource topology and security posture of the existing Bicep stack for the three in-scope components
- Expose two first-class `list(string)` variables for IP allowlisting: `ingress_allowed_ips` and `api_server_authorized_ips`
- Configure an Azure Storage remote state backend
- Support multiple environments via `.tfvars` files without code duplication

**Non-Goals:**
- Migration of PostgreSQL, ACR, or monitoring (separate phases)
- Deletion or replacement of existing Bicep files
- Terraforming the bootstrap storage account used for Terraform state (chicken-and-egg; created once by script or manually)
- Kubernetes-level resources (Helm charts, namespaces, RBAC bindings)

## Decisions

### 1. Root module + child modules, single state file

**Decision:** One root module calling three child modules (`modules/network`, `modules/aks`, `modules/keyvault`). A single `terraform apply` deploys all three. State lives in one Azure Storage blob.

**Rationale:** Cross-module role assignments (AGIC identity → AppGW Contributor; kubelet identity → ACR AcrPull) require both module outputs to be in scope simultaneously. A single root keeps these wiring points simple. Splitting into separate state roots would require `terraform_remote_state` data sources and coordinated apply ordering, adding complexity with no current benefit.

**Alternative considered:** Separate root modules per component with remote state references. Rejected — overkill for a single-cluster setup; introduces deploy ordering problems and state coupling.

### 2. Environment differentiation via `.tfvars`, not workspaces

**Decision:** `dev.tfvars` and `staging.tfvars` in `infra/terraform/`. Secrets injected at apply time via CI/CD environment variables (never committed).

**Rationale:** Terraform workspaces share a single configuration and differ only by workspace-namespaced state; resource names must still encode the environment to avoid collisions. Using `.tfvars` with an explicit `environment` variable is more transparent and is the dominant pattern in Azure Terraform projects. A `secrets.auto.tfvars` file pattern (gitignored) is documented for local development.

**Alternative considered:** Workspaces. Rejected — naming collision risk; workspace state is harder to inspect and audit separately.

### 3. `locals.tf` for naming and tagging

**Decision:** All resource names are computed in `locals.tf` at both the root and each child module level. A shared `tags` local is defined in the root and threaded into each module.

**Rationale:** Centralises the naming convention (`"${var.project_name}-${var.environment}-<suffix>"`) in one place. Avoids repetition across resources and makes renaming conventions a one-line change. This is idiomatic Terraform.

### 4. Ingress IP allowlist via NSG on the appgw-subnet

**Decision:** An NSG is attached to the `appgw-subnet`. An inbound security rule allows TCP 80/443 only from CIDRs in `var.ingress_allowed_ips`. All other inbound traffic on those ports is denied.

**Rationale:** The simplest, most maintainable enforcement point. An NSG is evaluated before traffic reaches the Application Gateway, so it provides network-layer enforcement regardless of AppGW configuration. Alternative WAF policy-based IP restrictions are more expensive and require WAF_v2 SKU.

**Alternative considered:** Application Gateway WAF IP restriction rules. Rejected — requires WAF_v2 SKU (higher cost), adds complexity; NSG achieves the same result for this use case.

### 5. API server access via `authorized_ip_ranges`

**Decision:** The AKS cluster's `api_server_access_profile.authorized_ip_ranges` is set from `var.api_server_authorized_ips`. `disableLocalAccounts` remains `true` and Entra ID Azure RBAC is used as in the Bicep baseline.

**Rationale:** Direct AKS feature for API server IP restriction. No additional infrastructure required. Pairs with `disableLocalAccounts = true` and Azure RBAC to give defence-in-depth: even if an IP is authorised, the caller still needs a valid Entra ID token with an appropriate cluster role.

### 6. Secrets as sensitive Terraform variables

**Decision:** Application secrets (DB passwords, JWT key, internal API key) are declared as `sensitive = true` string variables in `variables.tf`. They are never written to `.tfvars` files tracked in git; CI/CD injects them as environment variables (`TF_VAR_*`).

**Rationale:** Mirrors the Bicep `@secure()` pattern. Terraform marks sensitive values in plan output and state. The state file itself (in Azure Storage) should have access restricted to the pipeline service principal and authorised admins.

**Alternative considered:** Read secrets from an existing bootstrap Key Vault using `azurerm_key_vault_secret` data sources. Rejected for initial setup — creates a chicken-and-egg dependency (the KV module creates the vault; reading from it before apply would require a separate bootstrap KV). Can be adopted once the vault is stable.

### 7. azurerm provider ~> 4.x, `subscription_id` required

**Decision:** Pin `azurerm` to `~> 4.0` and `azuread` to `~> 3.0`. The `azurerm` provider block explicitly sets `subscription_id` (from a variable) and `features {}`.

**Rationale:** azurerm 4.x dropped many deprecated fields and consolidated resource schemas. Setting `subscription_id` explicitly (rather than relying on ambient CLI login) is required for CI/CD environments and is a hard requirement in azurerm 4.x.

## Risks / Trade-offs

- **State file contains sensitive values** → Mitigation: Azure Storage container access restricted to pipeline identity via RBAC; enable soft-delete and versioning on the storage account; consider enabling state encryption at rest.
- **Bootstrap chicken-and-egg** (the storage account for state can't be managed by the same Terraform) → Mitigation: Document a one-time bootstrap script (`scripts/bootstrap-tf-state.sh`) that creates the resource group, storage account, and container using `az` CLI.
- **Bicep and Terraform deployed side-by-side** → Risk of duplicate resource creation if both are applied to the same resource group. Mitigation: Use a separate resource group for Terraform deployments during the migration period, or import existing Bicep-managed resources into Terraform state using `terraform import` before decommissioning the Bicep templates.
- **AKS node pool changes require node-pool recreation** → Mitigation: `create_before_destroy` lifecycle on the node pool; document that VM size changes are destructive.
- **`authorized_ip_ranges` conflicts with private cluster** → The current design uses a public API server endpoint restricted by IP allowlist, not a private cluster. This is an acceptable posture for dev/staging; production may warrant a fully private cluster (separate phase decision).

## Migration Plan

1. **Bootstrap** (one-time, manual or script): Create Azure resource group, Storage Account, and blob container for Terraform state.
2. **Init**: `terraform init` with backend config pointing at the bootstrap storage account.
3. **First apply** (new resource group): Apply against a fresh resource group to validate the Terraform produces the expected resources without touching the Bicep-managed group.
4. **Validation**: Verify AKS cluster is reachable from allowed IPs only; verify API server is blocked from non-listed IPs; verify workload identity federated credentials are correct.
5. **Cut-over** (future): `terraform import` existing Bicep resources into state, then decommission the Bicep deployment. (Out of scope for this phase.)

**Rollback:** During the migration phase, the Bicep stack in the original resource group is untouched. Rolling back means simply deleting the Terraform-managed resource group.

## Open Questions

- Should `staging.tfvars` target the same Azure subscription as `dev.tfvars`, or a separate subscription? (Affects whether `subscription_id` is a per-environment tfvars value.)
- What CIDRs should be pre-populated in `dev.tfvars` for `api_server_authorized_ips` and `ingress_allowed_ips`? (Placeholder `0.0.0.0/0` used for now; to be replaced before first real deploy.)
- Will the CI/CD pipeline use a Service Principal or a Managed Identity for `terraform apply`? (Affects the `azurerm` provider `client_id`/`use_msi` configuration.)
