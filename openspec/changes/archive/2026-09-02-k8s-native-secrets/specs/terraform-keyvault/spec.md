## REMOVED Requirements

### Requirement: Key Vault provisioning in RBAC mode
**Reason**: Azure Key Vault is replaced by native Kubernetes Secrets. The `modules/keyvault` Terraform module is removed entirely. No Key Vault resource, access policies, or RBAC mode configuration is required.
**Migration**: Delete `infra/terraform/modules/keyvault/` and remove the module call from stage configurations (`stages/dev/main.tf`, `stages/staging/main.tf`). Remove all Key Vault outputs from stage root modules.

#### Scenario: Key Vault is created with RBAC authorization
- **WHEN** the keyvault module is applied
- **THEN** a Key Vault named `<project>-<env>-kv` SHALL exist with `rbac_authorization_enabled = true`, soft-delete enabled, and purge protection enabled

### Requirement: Per-service User-Assigned Managed Identities
**Reason**: Workload Identity and UAMIs were used exclusively to give pods access to Key Vault. With KV removed, the UAMIs and federated identity credentials serve no purpose and are removed.
**Migration**: Delete `azurerm_user_assigned_identity` and `azurerm_federated_identity_credential` resources. Remove UAMI outputs from the keyvault module and any references in stage modules.

#### Scenario: Four service identities are created
- **WHEN** the keyvault module is applied
- **THEN** four UAMIs SHALL exist, one per service, each named `<project>-<env>-<service>-identity`

### Requirement: Key Vault Secrets User role assignments
**Reason**: Removed along with Key Vault and UAMIs.
**Migration**: Delete `azurerm_role_assignment` resources for the `Key Vault Secrets User` role.

#### Scenario: Each service identity has Key Vault Secrets User on the vault
- **WHEN** the keyvault module is applied
- **THEN** a role assignment SHALL exist for each of the four service principal IDs on the Key Vault resource with role `Key Vault Secrets User`

### Requirement: AKS Workload Identity federated credentials
**Reason**: Removed along with Key Vault and UAMIs.
**Migration**: Delete `azurerm_federated_identity_credential` resources.

#### Scenario: Federated credential is created for each service
- **WHEN** the keyvault module is applied with `oidc_issuer_url` from the AKS cluster
- **THEN** each UAMI SHALL have one federated credential with issuer equal to the AKS OIDC URL and subject `system:serviceaccount:beer-tracker:<service-name>`

#### Scenario: Federated credential uses the correct audience
- **WHEN** the keyvault module is applied
- **THEN** each federated credential SHALL have audience `api://AzureADTokenExchange`

### Requirement: Application secrets stored in Key Vault
**Reason**: Secrets are now stored in a Kubernetes Secret (`beer-tracker-secrets`). Terraform no longer creates or manages secret resources.
**Migration**: Remove all `azurerm_key_vault_secret` resources. Secret lifecycle is now managed by `scripts/set-k8s-secrets.sh` and the CI/CD pipeline.

#### Scenario: All six secret slots are created after apply
- **WHEN** the keyvault module is applied
- **THEN** all six secrets SHALL exist in the Key Vault and be enabled, with value `"PLACEHOLDER"`

### Requirement: Module outputs for cross-module wiring
**Reason**: Removed along with the keyvault module. UAMI client IDs and KV URI are no longer needed by downstream consumers.
**Migration**: Remove `key_vault_name`, `key_vault_uri`, `key_vault_id`, and `*_service_client_id` outputs from stage root modules and any Helm value references.

#### Scenario: Required outputs are present after apply
- **WHEN** the keyvault module is applied
- **THEN** the following outputs SHALL be non-empty: `key_vault_name`, `key_vault_uri`, `key_vault_id`, `auth_service_client_id`, `beer_tracking_service_client_id`, `health_notification_service_client_id`, `statistics_service_client_id`
