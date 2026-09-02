## MODIFIED Requirements

### Requirement: Application secrets stored in Key Vault
The `modules/keyvault` module SHALL create the following six secret resources in the Key Vault with a static placeholder value (`"PLACEHOLDER"`): `auth-rs256-private-key`, `auth-db-password`, `tracking-db-password`, `notifications-db-password`, `statistics-db-password`, `internal-api-key`. Each secret resource SHALL have `lifecycle { ignore_changes = [value] }` so that Terraform never overwrites a value set externally. The module SHALL NOT accept sensitive variable inputs for secret values; secret content is exclusively managed by the bootstrap script outside of Terraform.

#### Scenario: All six secret slots are created after apply
- **WHEN** the keyvault module is applied
- **THEN** all six secrets SHALL exist in the Key Vault and be enabled, with value `"PLACEHOLDER"`

#### Scenario: No sensitive variables are accepted by the module
- **WHEN** the keyvault module interface is inspected
- **THEN** there SHALL be no variable declarations for `auth_rs256_private_key`, `auth_db_password`, `tracking_db_password`, `notifications_db_password`, `statistics_db_password`, or `internal_api_key`

#### Scenario: Terraform apply does not require secret env vars
- **WHEN** `terraform apply` is run for any stage without `TF_VAR_*` secret variables set
- **THEN** the apply SHALL succeed and create all six secret slots

#### Scenario: Externally set secret values are not overwritten
- **WHEN** the bootstrap script has set a real secret value and `terraform apply` is subsequently run
- **THEN** the secret value SHALL remain unchanged (not reverted to `"PLACEHOLDER"`)

## REMOVED Requirements

### Requirement: Secret values sourced from Terraform variables
**Reason**: Terraform variable injection of secrets requires `TF_VAR_*` environment variables on every plan/apply and couples secret rotation to Terraform runs. Secret management is moved to the bootstrap script (`scripts/set-keyvault-secrets.sh`).
**Migration**: Run `scripts/set-keyvault-secrets.sh --environment <env>` after `terraform apply` to populate real secret values. CI/CD pipelines that previously exported `TF_VAR_*` variables should be updated to call the bootstrap script instead.
