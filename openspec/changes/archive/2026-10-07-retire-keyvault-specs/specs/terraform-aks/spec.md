## MODIFIED Requirements

### Requirement: Workload Identity and OIDC issuer
The `modules/aks` module SHALL enable the OIDC issuer profile and Workload Identity security profile on the cluster, and the OIDC issuer URL SHALL be emitted as an output so that federated credentials for workload identities can be created. No workload in this repository currently uses them (secrets are native Kubernetes Secrets, see `kubernetes-secrets-bootstrap`). The OIDC issuer SHALL remain enabled: Azure does not allow disabling it once enabled, and the azurerm provider documents that disabling `oidc_issuer_enabled` forces a new cluster to be created. Workload Identity requires the OIDC issuer.

#### Scenario: OIDC issuer and Workload Identity enabled
- **WHEN** the aks module is applied
- **THEN** `oidc_issuer_enabled = true` and `workload_identity_enabled = true` SHALL be set on the cluster

#### Scenario: OIDC issuer URL is available as output
- **WHEN** the aks module is applied
- **THEN** the `oidc_issuer_url` output SHALL be a non-empty HTTPS URL

#### Scenario: Turning the OIDC issuer off is a deliberate replacement decision
- **WHEN** a change would set `oidc_issuer_enabled` to `false` or remove it from the module
- **THEN** the change SHALL state that the provider forces replacement of the cluster and SHALL include a reviewed `terraform plan` before it is applied

### Requirement: Add-ons — AGIC, Container Insights, Secrets Store CSI
The `modules/aks` module SHALL enable three add-ons: the Application Gateway Ingress Controller (AGIC) pointed at the Application Gateway ID passed as `var.app_gw_id`; Container Insights (omsagent) pointed at the Log Analytics workspace ID passed as `var.log_analytics_workspace_id` with AAD authentication enabled; and the Azure Key Vault Secrets Store CSI Driver with secret rotation enabled and a rotation poll interval of `2m`. The Secrets Store CSI Driver is currently unused by any workload in this repository; removing it is a separate infrastructure change that requires a reviewed `terraform plan`, because the effect of disabling it on the add-on's managed identity and on the node pool is not documented in the sources consulted.

#### Scenario: AGIC addon is enabled with the correct Application Gateway
- **WHEN** the aks module is applied with `app_gw_id` set
- **THEN** the `ingress_application_gateway` addon SHALL be enabled and reference the provided Application Gateway ID

#### Scenario: Container Insights addon sends to the correct workspace
- **WHEN** the aks module is applied with `log_analytics_workspace_id` set
- **THEN** the `oms_agent` addon SHALL be enabled with `log_analytics_workspace_id` set and `msi_auth_for_monitoring_enabled = true`

#### Scenario: Secrets Store CSI Driver is enabled with rotation
- **WHEN** the aks module is applied
- **THEN** the `key_vault_secrets_provider` addon SHALL be enabled with `secret_rotation_enabled = true` and `secret_rotation_interval = "2m"`

### Requirement: Module outputs for cross-module wiring
The `modules/aks` module SHALL expose outputs that the root module needs to create cross-module role assignments, and the OIDC issuer URL for federated credentials of workload identities.

#### Scenario: Required outputs are present after apply
- **WHEN** the aks module is applied
- **THEN** the following outputs SHALL be non-empty: `cluster_id`, `cluster_name`, `oidc_issuer_url`, `kubelet_identity_object_id`, `kubelet_identity_client_id`, `agic_identity_object_id`, `aks_identity_principal_id`
