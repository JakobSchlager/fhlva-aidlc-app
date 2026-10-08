## ADDED Requirements

### Requirement: Dev stage grants cluster-admin access to configured deployers
The dev stage `main.tf` SHALL define a local `aks_cluster_admin_object_ids` containing a list of Entra ID object IDs. For each entry the stage SHALL create one `azurerm_role_assignment` of the built-in role `Azure Kubernetes Service RBAC Cluster Admin`, scoped to the AKS cluster (`module.aks.cluster_id`). When the list is empty, the stage SHALL create no such assignment and SHALL still plan and apply without any variable, `.tfvars` file or environment variable.

#### Scenario: Listed user can use kubectl after apply
- **WHEN** a user's object ID is in the list and the dev stage is applied
- **THEN** that user holds the `Azure Kubernetes Service RBAC Cluster Admin` role on the AKS cluster and can run `kubectl apply` of a namespace after authenticating through kubelogin

#### Scenario: One assignment per listed object ID
- **WHEN** the list contains two object IDs
- **THEN** the plan contains two role assignments on the cluster, one per object ID

#### Scenario: Empty list creates nothing
- **WHEN** the list is empty
- **THEN** no cluster-admin role assignment is planned and `terraform plan` succeeds without extra inputs

#### Scenario: Assignment is scoped to the cluster only
- **WHEN** the dev stage is applied with a non-empty list
- **THEN** the role assignment scope SHALL be the AKS cluster resource and SHALL NOT be the subscription or resource group
