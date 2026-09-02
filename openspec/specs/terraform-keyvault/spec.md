## Status: RETIRED

The `modules/keyvault` Terraform module has been removed entirely. Azure Key Vault is replaced by native Kubernetes Secrets (`beer-tracker-secrets`). The UAMIs, federated credentials, Key Vault resource, role assignments, and secret slots previously managed by this module no longer exist. See `kubernetes-secrets-bootstrap` for the replacement approach.

## Purpose

Specifies requirements for the `modules/keyvault` Terraform module, which provisions an Azure Key Vault, per-service managed identities, AKS Workload Identity federated credentials, and application secrets for the Beer Tracker services.

## Requirements

### Requirement: Key Vault provisioning in RBAC mode
The `modules/keyvault` module SHALL create an Azure Key Vault with standard SKU, RBAC authorization mode (`rbac_authorization_enabled = true`), soft-delete enabled with 90-day retention, purge protection enabled, and public network access enabled. Access policies SHALL NOT be used; all access is governed by Azure RBAC role assignments.

#### Scenario: Key Vault is created with RBAC authorization
- **WHEN** the keyvault module is applied
- **THEN** a Key Vault named `<project>-<env>-kv` SHALL exist with `rbac_authorization_enabled = true`, soft-delete enabled, and purge protection enabled

#### Scenario: Key Vault is accessible over public network
- **WHEN** the keyvault module is applied
- **THEN** `public_network_access_enabled` SHALL be `true` and the network ACL default action SHALL be `Allow`

### Requirement: Per-service User-Assigned Managed Identities
The `modules/keyvault` module SHALL create one User-Assigned Managed Identity for each of the four services: `auth-service`, `beer-tracking-service`, `health-notification-service`, and `statistics-service`. Each identity SHALL be named `<project>-<env>-<service-name>-identity`.

#### Scenario: Four service identities are created
- **WHEN** the keyvault module is applied
- **THEN** four UAMIs SHALL exist, one per service, each named `<project>-<env>-<service>-identity`

### Requirement: Key Vault Secrets User role assignments
The `modules/keyvault` module SHALL grant each service UAMI the built-in `Key Vault Secrets User` role (role definition ID `4633458b-17de-408a-b874-0445c86b69e6`) scoped to the Key Vault. This allows each service to read secrets via the Secrets Store CSI Driver or the Azure SDK.

#### Scenario: Each service identity has Key Vault Secrets User on the vault
- **WHEN** the keyvault module is applied
- **THEN** a role assignment SHALL exist for each of the four service principal IDs on the Key Vault resource with role `Key Vault Secrets User`

### Requirement: AKS Workload Identity federated credentials
The `modules/keyvault` module SHALL create a Federated Identity Credential for each service UAMI, binding it to the corresponding Kubernetes service account in namespace `beer-tracker`. The credential SHALL reference the OIDC issuer URL passed as `var.oidc_issuer_url` and use audience `api://AzureADTokenExchange`. The Kubernetes service account name SHALL match the service name (e.g. `auth-service`).

#### Scenario: Federated credential is created for each service
- **WHEN** the keyvault module is applied with `oidc_issuer_url` from the AKS cluster
- **THEN** each UAMI SHALL have one federated credential with issuer equal to the AKS OIDC URL and subject `system:serviceaccount:beer-tracker:<service-name>`

#### Scenario: Federated credential uses the correct audience
- **WHEN** the keyvault module is applied
- **THEN** each federated credential SHALL have audience `api://AzureADTokenExchange`

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

### Requirement: Module outputs for cross-module wiring
The `modules/keyvault` module SHALL expose the Key Vault name, URI, resource ID, and the client IDs of all four service identities so the root module and downstream consumers (Helm values, CI/CD scripts) can reference them.

#### Scenario: Required outputs are present after apply
- **WHEN** the keyvault module is applied
- **THEN** the following outputs SHALL be non-empty: `key_vault_name`, `key_vault_uri`, `key_vault_id`, `auth_service_client_id`, `beer_tracking_service_client_id`, `health_notification_service_client_id`, `statistics_service_client_id`
