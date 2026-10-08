## 1. Confirm role facts

- [x] 1.1 Run `az role definition list --name "Azure Kubernetes Service RBAC Cluster Admin"` and confirm the data actions include namespaces and secrets write. Not run; confirmed by outcome instead: `kubectl` worked after the assignment (reported by the project owner, 2026-10-08)
- [x] 1.2 Obtain the user object ID(s) to grant (`az ad signed-in-user show --query id -o tsv`) and add them to `local.aks_cluster_admin_object_ids`. Done by the project owner

## 2. Terraform

- [x] 2.1 In `infra/terraform/stages/dev/main.tf` add the local `aks_cluster_admin_object_ids` (list of strings, empty by default, with a comment on how to find an object ID), adding lines only and leaving the existing uncommitted edits untouched
- [x] 2.2 Add an `azurerm_role_assignment` using `for_each = toset(local.aks_cluster_admin_object_ids)`, `principal_id = each.value`, `scope = module.aks.cluster_id`, `role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"`, next to the other role assignments
- [x] 2.3 Run `terraform init -backend=false && terraform validate` in `infra/terraform/stages/dev/`
- [x] 2.4 Run `terraform plan` (if backend access is available) and confirm one assignment per listed object ID and no unrelated changes; with an empty list confirm none is planned. The plan with an empty list showed no assignment (15 to add, output supplied by the project owner, 2026-10-08); the apply with the object ID set was run by the project owner, who reports `kubectl` worked afterwards; that plan output was not seen

## 3. Documentation

- [x] 3.1 In `README.md` prerequisites for the Azure setup, state that cluster access needs the Cluster Admin data-plane role and that Terraform grants it to the users whose object IDs are listed in `local.aks_cluster_admin_object_ids`
- [x] 3.2 Add a `README.md` troubleshooting row for `... User does not have access to the resource in Azure. Update role assignment to allow access.` with the `az role assignment create --assignee <upn-or-object-id> --role "Azure Kubernetes Service RBAC Cluster Admin" --scope <cluster-id>` workaround and a note that propagation may take a few minutes
- [x] 3.3 Mark any unrun step with `VERIFY` (the first real apply, and kubectl after the assignment)
