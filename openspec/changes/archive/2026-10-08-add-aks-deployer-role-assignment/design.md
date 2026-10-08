## Context

`modules/aks` sets `local_account_disabled = true` and `azure_rbac_enabled = true`, so authorization to the Kubernetes API is decided by Azure role assignments with data actions. The role assignments in `stages/dev/main.tf` cover only managed identities (AGIC and the kubelet). `scripts/deploy-azure.sh` runs `kubectl apply` for a namespace, installs PostgreSQL with Helm, creates secrets and deploys the chart; `scripts/set-k8s-secrets.sh` creates secrets. Failure observed from the devcontainer: `namespaces "beer-tracker" is forbidden: User "michael.krieger@dynatrace.com" cannot get resource "namespaces" ... User does not have access to the resource in Azure. Update role assignment to allow access.` This shows that kubelogin authentication works and authorization is what is missing (kubelogin itself was added in the archived change `2026-10-08-add-kubelogin-to-devcontainer`).

The stage's current spec (`terraform-stage-dev`) requires that it initialises and applies with no `-backend-config`, `.tfvars` or `TF_VAR_*`, with all non-secret configuration as `locals`.

Built-in role facts, from [Azure built-in roles: Containers](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers) (read 2026-10-08; extracted through a page-summarising tool, so re-check the data actions before relying on them):

| Role | Namespaces write | Secrets write | Note |
|---|---|---|---|
| Azure Kubernetes Service RBAC Cluster Admin | yes | yes | "manage all resources in the cluster" |
| Azure Kubernetes Service RBAC Admin | no (excluded) | yes | "except update or delete resource quotas and namespaces" |
| Azure Kubernetes Service RBAC Writer | no (read only) | yes | no roles/bindings, no CRDs |
| Azure Kubernetes Service RBAC Reader | no | no | read-only |

## Goals / Non-Goals

**Goals:**
- After `terraform apply`, the listed users can run `scripts/deploy-azure.sh` and `scripts/set-k8s-secrets.sh` without manual role assignments.
- Several deployers can be granted access by editing one list.

**Non-Goals:**
- Giving the GitHub Actions service principal cluster access (the existing spec scenario for it is not implemented here, and no pipeline is in scope).
- Namespace-scoped or least-privilege roles for day-to-day use.
- Changing how `az aks get-credentials` or kubelogin are configured.

## Decisions

**D1: Assign `Azure Kubernetes Service RBAC Cluster Admin`.**
The deploy script creates the `beer-tracker` namespace, and per the role table above only Cluster Admin may write namespaces; Admin and Writer would fail on that step. Alternative: pre-create the namespace in Terraform (or by hand) and use Writer or Admin; rejected for now because the Helm/PostgreSQL steps may also need cluster-scoped resources, which has not been checked, and the scripts should keep working unchanged. Matches the role the `azure-aks-deployment` spec already names.

**D2: Scope the assignment to the cluster (`module.aks.cluster_id`).**
The module already outputs `cluster_id`. Cluster scope is the narrowest scope that allows namespace creation.

**D3: Take a list of user object IDs.**
`for_each` over `toset(local.aks_cluster_admin_object_ids)` creates one `azurerm_role_assignment` per Entra ID object ID, so each instructor can add their own. Alternatives: a single string (rejected: several instructors share the repository), an Entra group (membership changes would need no Terraform change; not chosen, the list can hold a group's object ID later), a `data.azuread_user` lookup by UPN (adds the `azuread` provider and directory read permission; rejected), or a hard-coded ID in the resource (rejected).

**D4: Keep the list in the stage's `locals`, default empty.**
The `terraform-stage-dev` spec says all non-secret configuration is `locals` and that plan and apply need no `TF_VAR_*` or `.tfvars`. A local satisfies both without an exception; an empty list creates no assignment. The cost is that object IDs are committed to the repository. They are identifiers, not secrets, but they tie people to the repository (the stage already contains an email address). An earlier iteration used a variable so no ID would be committed; the owner chose a local.

**D5: Place the local and the resource in `stages/dev/main.tf`, the resource next to the other role assignments**, not in `modules/aks`, because assignments for managed identities already live there and the module has no notion of human principals.

**D6: Document the manual workaround in the README troubleshooting table**, because the first apply of this change can only happen after someone with role-assignment rights runs it.

## Risks / Trade-offs

- [Cluster Admin is broad; the listed users can read all secrets and change RBAC] → Grant it to as few users as needed; revisit scoping (or a group) if more people need access.
- [The first apply needs `roleAssignments/write`] → Same requirement as the existing role assignments; documented in README.
- [Role assignments take minutes to propagate and tokens may be cached] → Note in the troubleshooting row to retry after a few minutes or fetch a fresh token. Propagation time itself is not measured.
- [Edits to `stages/dev/main.tf` collide with uncommitted user edits] → Add the new lines only; do not rewrite existing locals.
- [Role data actions were read through a summarising fetch] → Confirm against the role definition (`az role definition list --name "Azure Kubernetes Service RBAC Cluster Admin"`) during implementation.

## Update 2026-10-08

The project owner added an object ID to `local.aks_cluster_admin_object_ids`, ran `terraform apply`, and reports that `kubectl` worked without any manual role assignment. This confirms D1 and D2 in practice (Cluster Admin at cluster scope was sufficient for `kubectl` access). The deploy scripts themselves were not re-run for this check, and the role's data actions were not read with `az role definition list`.

## Open Questions

- Should an Entra group's object ID replace the individual IDs once the team settles? A user's object ID is found with `az ad signed-in-user show --query id -o tsv`.
- Should the GitHub Actions service principal be granted the same role in this or a separate change?
- Does `az aks get-credentials` also require `Azure Kubernetes Service Cluster User Role`? It worked for the current user without a listed assignment, probably through Owner/Contributor; not verified for a user without those roles.
