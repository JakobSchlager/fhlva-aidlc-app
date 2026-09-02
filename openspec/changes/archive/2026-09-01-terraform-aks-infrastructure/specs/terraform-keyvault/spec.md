## ADDED Requirements

### Requirement: Key Vault provisioning in RBAC mode
The `modules/keyvault` module SHALL create an Azure Key Vault with standard SKU, RBAC authorization mode (`enable_rbac_authorization = true`), soft-delete enabled with 90-day retention, purge protection enabled, and public network access enabled. Access policies SHALL NOT be used; all access is governed by Azure RBAC role assignments.

#### Scenario: Key Vault is created with RBAC authorization
- **WHEN** the keyvault module is applied
- **THEN** a Key Vault named `<project>-<env>-kv` SHALL exist with `enable_rbac_authorization = true`, soft-delete enabled, and purge protection enabled

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
The `modules/keyvault` module SHALL create the following six secrets in the Key Vault. Each secret value SHALL come from a corresponding `sensitive` Terraform variable. Secret names: `auth-rs256-private-key`, `auth-db-password`, `tracking-db-password`, `notifications-db-password`, `statistics-db-password`, `internal-api-key`.

#### Scenario: All six secrets are present in the vault after apply
- **WHEN** the keyvault module is applied with non-empty values for all six secret variables
- **THEN** all six secrets SHALL exist in the Key Vault and be enabled

#### Scenario: Secret values are never exposed in Terraform plan output
- **WHEN** a `terraform plan` is run
- **THEN** secret variable values SHALL be redacted (`(sensitive value)`) in the plan output due to `sensitive = true`

### Requirement: Module outputs for cross-module wiring
The `modules/keyvault` module SHALL expose the Key Vault name, URI, resource ID, and the client IDs of all four service identities so the root module and downstream consumers (Helm values, CI/CD scripts) can reference them.

#### Scenario: Required outputs are present after apply
- **WHEN** the keyvault module is applied
- **THEN** the following outputs SHALL be non-empty: `key_vault_name`, `key_vault_uri`, `key_vault_id`, `auth_service_client_id`, `beer_tracking_service_client_id`, `health_notification_service_client_id`, `statistics_service_client_id`
