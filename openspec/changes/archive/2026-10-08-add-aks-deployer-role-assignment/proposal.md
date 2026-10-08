## Why

The AKS cluster has local accounts disabled and Azure RBAC enabled, so `kubectl` only works for identities that hold an Azure Kubernetes Service RBAC data-plane role. The existing `azure-aks-deployment` spec assumes an operator "with the `Azure Kubernetes Service RBAC Cluster Admin` role", but nothing in Terraform assigns it. A person who provisions the cluster (Owner, or Contributor + User Access Administrator) therefore still gets `Forbidden ... User does not have access to the resource in Azure` from `scripts/deploy-azure.sh` at its first `kubectl apply`, as happened from the devcontainer.

## What Changes

- The dev stage assigns the built-in role `Azure Kubernetes Service RBAC Cluster Admin`, scoped to the AKS cluster, to a list of Entra ID users, given by object ID, so a `terraform apply` leaves those users able to run the deploy scripts.
- The object IDs are a new list in the `locals` block of `infra/terraform/stages/dev/main.tf` (`aks_cluster_admin_object_ids`): with an empty list no role assignment is created, so plan and apply still need no inputs.
- `README.md` gets a note in the Azure prerequisites and a troubleshooting row for the `Forbidden ... Update role assignment` error, including the one-line `az role assignment create` workaround.
- No change to the AKS module, the cluster configuration or the deploy scripts.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `terraform-stage-dev`: gains a requirement that the dev stage grants the cluster-admin data-plane role on the AKS cluster to the users whose object IDs are listed in a local. Added as a new requirement; no existing requirement text changes.

## Impact

- `infra/terraform/stages/dev/main.tf`: one new local and one `azurerm_role_assignment` (using `for_each`). The file has uncommitted user edits (subscription ID, IP allowlists, alert email); the change must be applied on top of them without touching those lines.
- `README.md`: prerequisites and troubleshooting.
- Applying it requires `Microsoft.Authorization/roleAssignments/write`, already required for the existing role assignments (README, "Required permissions").
- Granting Cluster Admin is broad (see design, Risks).
- Object IDs of the listed users are committed to the repository (identifiers, not secrets).
