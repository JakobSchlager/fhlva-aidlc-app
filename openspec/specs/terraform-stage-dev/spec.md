## Purpose

Specifies requirements for the `infra/terraform/stages/dev/` Terraform root, which is the self-contained deployment unit for the dev environment. All configuration is expressed as `locals`; no Terraform variables or external flags are required to initialise or apply.
## Requirements
### Requirement: Self-contained dev stage Terraform root
The `infra/terraform/stages/dev/` directory SHALL be a self-contained Terraform root that can be initialised and applied without any `-backend-config` flags, environment variables, or `.tfvars` file arguments. All non-secret configuration SHALL be defined as `locals` within the stage.

#### Scenario: Init requires no flags
- **WHEN** a user runs `terraform init` inside `infra/terraform/stages/dev/`
- **THEN** the command SHALL succeed without any `-backend-config` arguments

#### Scenario: Plan and apply require no env vars
- **WHEN** a user runs `terraform plan` or `terraform apply` inside `infra/terraform/stages/dev/`
- **THEN** the command SHALL succeed without any `TF_VAR_*` environment variables set

### Requirement: Fully specified dev backend configuration
The dev stage `backend.tf` SHALL contain a complete `azurerm` backend block with `resource_group_name`, `storage_account_name`, `container_name`, and `key` all hardcoded. The state key SHALL be `dev/terraform.tfstate`.

#### Scenario: Backend is fully specified
- **WHEN** the dev stage `backend.tf` is read
- **THEN** it SHALL contain no placeholder values and no partial configuration requiring external override

### Requirement: Dev environment locals
The dev stage `main.tf` SHALL define a `locals` block containing at minimum: `subscription_id` (dev Azure subscription), `project_name` (`"beertracker"`), `environment` (`"dev"`), `location` (`"germanywestcentral"`), `ingress_allowed_ips`, and `api_server_authorized_ips`.

#### Scenario: Locals are set for dev
- **WHEN** the dev stage `main.tf` is read
- **THEN** a `locals` block SHALL exist with the dev-specific subscription ID and environment name `"dev"`

### Requirement: Dev stage calls all root modules
The dev stage `main.tf` SHALL call the `network`, `aks`, and `acr` modules using relative paths (`../../modules/<name>`), passing values from `local.*` rather than `var.*`. The `acr` module SHALL receive `resource_group_name` from `data.azurerm_resource_group.main.name`. The `kubelet_acr_pull` role assignment SHALL reference `module.acr.acr_id` as its scope; the empty `acr_id = ""` local placeholder SHALL be removed.

#### Scenario: Module sources use relative paths
- **WHEN** the dev stage `main.tf` is read
- **THEN** each module block (`network`, `aks`, `acr`) SHALL have `source = "../../modules/<name>"` and all required inputs SHALL reference `local.*` values

#### Scenario: Kubelet identity gets AcrPull on the ACR
- **WHEN** the dev stage is applied
- **THEN** a role assignment of `AcrPull` SHALL exist on the ACR resource scoped to the kubelet managed identity (`module.aks.kubelet_identity_object_id`)

### Requirement: Dev stage exposes ACR login server output
The dev stage `outputs.tf` SHALL expose `acr_login_server` sourced from `module.acr.acr_login_server`, so deploy scripts can discover the registry endpoint from Terraform output without hardcoding.

#### Scenario: ACR login server is available as a Terraform output
- **WHEN** `terraform output acr_login_server` is run in `infra/terraform/stages/dev/`
- **THEN** it SHALL return the FQDN of the provisioned container registry (e.g. `fhooeaidlcdevacr.azurecr.io`)

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
