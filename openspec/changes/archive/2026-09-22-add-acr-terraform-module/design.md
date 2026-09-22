## Context

The project has no Azure Container Registry under Terraform management. `infra/terraform/stages/dev/main.tf` contains `acr_id = ""` as a placeholder local; the `kubelet_acr_pull` role assignment is gated behind `for_each = local.acr_id != "" ? toset([local.acr_id]) : toset([])`, so it is never created. As a result, the AKS kubelet identity cannot pull images from any ACR, and Helm deployment of application workloads is blocked.

A Bicep equivalent (`infra/acr.bicep`) exists but was never applied. The Terraform module reproduces that configuration faithfully and becomes the authoritative source going forward.

## Goals / Non-Goals

**Goals:**
- Create a reusable `modules/acr/` Terraform module following the same structure as `modules/aks/`, `modules/network/`, and `modules/keyvault/`
- Wire the module into `stages/dev/main.tf`, replacing the empty `acr_id = ""` placeholder
- Simplify the `kubelet_acr_pull` role assignment from a conditional `for_each` to a plain resource now that ACR is always present
- Expose `acr_login_server` as a stage output so deploy scripts can discover the registry without hardcoding

**Non-Goals:**
- Private endpoint or VNet integration for ACR (public endpoint is sufficient; AKS pulls over the public endpoint)
- Geo-replication or Premium SKU features
- CI/CD pipeline changes — image build and push remain a script/pipeline concern outside Terraform
- Staging environment wiring (out of scope for this change)

## Decisions

### Decision 1: Standard SKU

**Chosen:** `Standard`

**Alternatives considered:**
- *Basic*: No retention policies, no webhooks, lower throughput limits — not suitable even for dev since retention policy is configured to match the Bicep baseline.
- *Premium*: Adds private endpoints, geo-replication, and dedicated throughput — unnecessary overhead for this workload and would require VNet changes.

Standard matches the existing Bicep configuration and provides retention policies and webhook support at reasonable cost.

### Decision 2: `resource_group_name` as a module variable, not a data source inside the module

**Chosen:** Accept `resource_group_name` as a string variable.

The stage root already has `data.azurerm_resource_group.main` and passes its `.name` to other modules (e.g. `module "aks"`). Adding a duplicate data source inside `modules/acr/` would be redundant and creates an implicit dependency. Passing the name as a variable keeps the module stateless with respect to resource group lookups and is consistent with how `modules/aks/` and `modules/keyvault/` are structured.

### Decision 3: Replace the conditional `for_each` on `kubelet_acr_pull` with a plain resource

**Chosen:** Remove the `for_each` conditional entirely; use a direct `scope = module.acr.acr_id`.

The `for_each = local.acr_id != "" ? toset([local.acr_id]) : toset([])` pattern existed solely to make the role assignment optional when ACR was not yet managed by Terraform. Once the ACR module is wired in, ACR is always present and the conditional is dead code. A plain `azurerm_role_assignment` resource is clearer.

**State impact:** Because the existing `for_each` never had any instances (empty set), Terraform state has no record of this resource. The new plain resource will be created fresh — no `terraform state mv` is needed.

### Decision 4: ACR naming — strip hyphens from project name

**Chosen:** `lower(replace("${var.project_name}${var.environment}acr", "-", ""))`

ACR names must be globally unique, 5–50 characters, and alphanumeric only. Stripping hyphens from the project name (`fhooe-aidlc` → `fhooeaidlc`) and appending `environment` + `acr` produces `fhooeaidlcdevacr` (16 chars). This exactly matches the Bicep convention and avoids a separate name-generation variable.

## Risks / Trade-offs

- **ACR name collision**: The derived name `fhooeaidlcdevacr` must be globally unique across all Azure tenants. If already taken, `terraform apply` will fail with a conflict error.
  → *Mitigation*: Check with `az acr show --name fhooeaidlcdevacr` before applying. If taken, append a short numeric suffix to `project_name` in the stage locals.

- **`terraform init` required after adding the module**: The new `modules/acr/` directory is a local module; `terraform init` must be re-run in `stages/dev/` before plan/apply.
  → No mitigation needed — this is standard Terraform behaviour; document it in the task list.

- **Role assignment `for_each` → plain resource**: The resource address changes from `azurerm_role_assignment.kubelet_acr_pull["<id>"]` to `azurerm_role_assignment.kubelet_acr_pull`. Since the `for_each` was always empty, no existing state entry is affected. If for any reason the role assignment was created outside Terraform and imported, the import address would need updating.
  → Low risk given the empty `for_each` history; no action required.

## Migration Plan

1. Write `infra/terraform/modules/acr/{main.tf,variables.tf,outputs.tf,locals.tf}`
2. Update `infra/terraform/stages/dev/main.tf`:
   - Add `module "acr"` block pointing to `../../modules/acr`
   - Remove `acr_id = ""` from `locals`
   - Change `azurerm_role_assignment.kubelet_acr_pull` from `for_each` to a plain resource with `scope = module.acr.acr_id`
3. Update `infra/terraform/stages/dev/outputs.tf`: add `acr_login_server` output
4. Run `terraform init` in `infra/terraform/stages/dev/`
5. Run `terraform plan` — expected: create 1 ACR + 1 role assignment, no other changes
6. Run `terraform apply`
7. Verify: `terraform output acr_login_server` returns `fhooeaidlcdevacr.azurecr.io`

**Rollback:** Delete the ACR resource and remove the module block. The AKS cluster is unaffected — it continues running without image pull capability (identical to current state).

## Open Questions

- None — scope is fully determined by the IP exhaustion constraint in the existing kubelet identity setup and the Bicep baseline.
