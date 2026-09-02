## ADDED Requirements

### Requirement: Self-contained staging stage Terraform root
The `infra/terraform/stages/staging/` directory SHALL be a self-contained Terraform root that can be initialised and applied without any `-backend-config` flags, environment variables, or `.tfvars` file arguments. All non-secret configuration SHALL be defined as `locals` within the stage.

#### Scenario: Init requires no flags
- **WHEN** a user runs `terraform init` inside `infra/terraform/stages/staging/`
- **THEN** the command SHALL succeed without any `-backend-config` arguments

#### Scenario: Plan and apply require no env vars
- **WHEN** a user runs `terraform plan` or `terraform apply` inside `infra/terraform/stages/staging/`
- **THEN** the command SHALL succeed without any `TF_VAR_*` environment variables set

### Requirement: Fully specified staging backend configuration
The staging stage `backend.tf` SHALL contain a complete `azurerm` backend block with `resource_group_name`, `storage_account_name`, `container_name`, and `key` all hardcoded. The state key SHALL be `staging/terraform.tfstate`, distinct from the dev state key.

#### Scenario: Backend is fully specified with staging key
- **WHEN** the staging stage `backend.tf` is read
- **THEN** it SHALL contain no placeholder values and the state key SHALL be `staging/terraform.tfstate`

### Requirement: Staging environment locals with separate subscription
The staging stage `main.tf` SHALL define a `locals` block containing at minimum: `subscription_id` (staging Azure subscription, different from dev), `project_name` (`"beertracker"`), `environment` (`"staging"`), `location` (`"germanywestcentral"`), `ingress_allowed_ips`, and `api_server_authorized_ips`.

#### Scenario: Staging uses a different subscription ID than dev
- **WHEN** both stage `main.tf` files are compared
- **THEN** the `subscription_id` local SHALL differ between dev and staging

#### Scenario: Environment local is set to staging
- **WHEN** the staging stage `main.tf` is read
- **THEN** the `environment` local SHALL be `"staging"`

### Requirement: Staging stage calls all root modules
The staging stage `main.tf` SHALL call the `network`, `aks`, and `keyvault` modules using relative paths (`../../modules/<name>`), passing values from `local.*` rather than `var.*`.

#### Scenario: Module sources use relative paths
- **WHEN** the staging stage `main.tf` is read
- **THEN** each module block SHALL have `source = "../../modules/<name>"` and all required inputs SHALL reference `local.*` values
