## ADDED Requirements

### Requirement: ACR resource provisioning
The `modules/acr` module SHALL create an Azure Container Registry with the following fixed configuration: Standard SKU, admin user disabled, anonymous pull disabled, public network access enabled, zone redundancy disabled, image retention policy of 30 days (enabled), and soft-delete policy of 7 days (enabled). The registry name SHALL be derived by concatenating `project_name`, `environment`, and the literal suffix `acr`, stripping any hyphens, and lowercasing the result (e.g. `fhooeaidlcdevacr`). Tags SHALL be applied from the `tags` variable.

#### Scenario: ACR exists with correct name after apply
- **WHEN** the acr module is applied with `project_name = "fhooe-aidlc"` and `environment = "dev"`
- **THEN** a container registry named `fhooeaidlcdevacr` SHALL exist in the target resource group

#### Scenario: Admin user is disabled
- **WHEN** the acr module is applied
- **THEN** `adminUserEnabled` SHALL be `false` on the registry

#### Scenario: Anonymous pull is disabled
- **WHEN** the acr module is applied
- **THEN** `anonymousPullEnabled` SHALL be `false` on the registry

#### Scenario: Public network access is enabled
- **WHEN** the acr module is applied
- **THEN** `publicNetworkAccess` SHALL be `Enabled` so AKS nodes can pull images over the public endpoint without private link

### Requirement: ACR module variables
The `modules/acr` module SHALL accept the following input variables: `project_name` (string), `environment` (string), `location` (string), `resource_group_name` (string), and `tags` (map of strings). All variables are required with no defaults.

#### Scenario: Module accepts standard project variables
- **WHEN** the module is called with `project_name`, `environment`, `location`, `resource_group_name`, and `tags`
- **THEN** `terraform validate` SHALL succeed with no errors

### Requirement: ACR module outputs
The `modules/acr` module SHALL expose the following outputs: `acr_id` (the resource ID of the registry, used to scope role assignments) and `acr_login_server` (the FQDN login server, used by deploy scripts to push and reference images).

#### Scenario: Outputs are populated after apply
- **WHEN** the acr module is applied
- **THEN** `acr_id` SHALL be a non-empty Azure resource ID string and `acr_login_server` SHALL be a non-empty FQDN ending in `.azurecr.io`
