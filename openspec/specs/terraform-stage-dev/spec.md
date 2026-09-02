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
The dev stage `main.tf` SHALL call the `network`, `aks`, and `keyvault` modules using relative paths (`../../modules/<name>`), passing values from `local.*` rather than `var.*`.

#### Scenario: Module sources use relative paths
- **WHEN** the dev stage `main.tf` is read
- **THEN** each module block SHALL have `source = "../../modules/<name>"` and all required inputs SHALL reference `local.*` values
