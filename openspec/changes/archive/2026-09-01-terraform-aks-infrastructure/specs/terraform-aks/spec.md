## ADDED Requirements

### Requirement: AKS control-plane managed identity
The `modules/aks` module SHALL create a User-Assigned Managed Identity for the AKS control plane and assign it the `Network Contributor` role on the AKS subnet. The AKS cluster SHALL use this identity as its control-plane identity (`identity.type = "UserAssigned"`).

#### Scenario: Control-plane identity exists and has Network Contributor on AKS subnet
- **WHEN** the aks module is applied with `aks_subnet_id` provided
- **THEN** a UAMI named `<project>-<env>-aks-identity` SHALL exist, and a Network Contributor role assignment SHALL be present on the AKS subnet scoped to that identity's principal ID

### Requirement: AKS cluster provisioning
The `modules/aks` module SHALL create a managed AKS cluster with the following fixed configuration: Kubernetes version `1.30`, Azure RBAC enabled, local accounts disabled, Entra ID managed integration with `enableAzureRBAC: true`, Azure CNI network plugin with azure network policy, service CIDR `10.1.0.0/16`, DNS service IP `10.1.0.10`, and standard load balancer with `loadBalancer` outbound type. The cluster SHALL use the AKS subnet passed as `var.aks_subnet_id`.

#### Scenario: Cluster exists with correct Kubernetes version
- **WHEN** the aks module is applied
- **THEN** a cluster named `<project>-<env>-aks` SHALL exist running Kubernetes `1.30`

#### Scenario: Local accounts are disabled and Azure RBAC is active
- **WHEN** the aks module is applied
- **THEN** `disable_local_accounts` SHALL be `true` and the AAD profile SHALL have `azure_rbac_enabled = true`

#### Scenario: Azure CNI networking is configured
- **WHEN** the aks module is applied
- **THEN** the network profile SHALL use `network_plugin = "azure"` and `network_policy = "azure"`

### Requirement: System node pool with autoscaling
The `modules/aks` module SHALL create a single system node pool named `system` with VM size `Standard_D2s_v3`, OS disk size 128 GB, OS disk type `Managed`, OS type `Linux`, OS SKU `AzureLinux`, minimum node count 2, maximum node count 5, max pods per node 110, and max surge upgrade setting of `33%`.

#### Scenario: Node pool autoscaling is active within bounds
- **WHEN** the aks module is applied
- **THEN** the system node pool SHALL have `enable_auto_scaling = true`, `min_count = 2`, and `max_count = 5`

#### Scenario: Node pool uses AzureLinux on Standard_D2s_v3
- **WHEN** the aks module is applied
- **THEN** `vm_size` SHALL be `Standard_D2s_v3` and `os_sku` SHALL be `AzureLinux`

### Requirement: Workload Identity and OIDC issuer
The `modules/aks` module SHALL enable the OIDC issuer profile and Workload Identity security profile on the cluster. The OIDC issuer URL SHALL be emitted as an output for use by the Key Vault module when creating federated credentials.

#### Scenario: OIDC issuer and Workload Identity enabled
- **WHEN** the aks module is applied
- **THEN** `oidc_issuer_enabled = true` and `workload_identity_enabled = true` SHALL be set on the cluster

#### Scenario: OIDC issuer URL is available as output
- **WHEN** the aks module is applied
- **THEN** the `oidc_issuer_url` output SHALL be a non-empty HTTPS URL

### Requirement: Add-ons — AGIC, Container Insights, Secrets Store CSI
The `modules/aks` module SHALL enable three add-ons: the Application Gateway Ingress Controller (AGIC) pointed at the Application Gateway ID passed as `var.app_gw_id`; Container Insights (omsagent) pointed at the Log Analytics workspace ID passed as `var.log_analytics_workspace_id` with AAD authentication enabled; and the Azure Key Vault Secrets Store CSI Driver with secret rotation enabled and a rotation poll interval of `2m`.

#### Scenario: AGIC addon is enabled with the correct Application Gateway
- **WHEN** the aks module is applied with `app_gw_id` set
- **THEN** the `ingress_application_gateway` addon SHALL be enabled and reference the provided Application Gateway ID

#### Scenario: Container Insights addon sends to the correct workspace
- **WHEN** the aks module is applied with `log_analytics_workspace_id` set
- **THEN** the `oms_agent` addon SHALL be enabled with `log_analytics_workspace_id` set and `msi_auth_for_monitoring_enabled = true`

#### Scenario: Secrets Store CSI Driver is enabled with rotation
- **WHEN** the aks module is applied
- **THEN** the `key_vault_secrets_provider` addon SHALL be enabled with `secret_rotation_enabled = true` and `secret_rotation_interval = "2m"`

### Requirement: Auto-upgrade configuration
The `modules/aks` module SHALL configure the cluster with `patch` upgrade channel and `NodeImage` node OS upgrade channel.

#### Scenario: Auto-upgrade channels are set
- **WHEN** the aks module is applied
- **THEN** `automatic_upgrade_channel = "patch"` and `node_os_upgrade_channel = "NodeImage"` SHALL be set

### Requirement: API server IP allowlist
The `modules/aks` module SHALL accept an `api_server_authorized_ips` variable of type `list(string)`. The AKS API server `authorized_ip_ranges` SHALL be set from this variable. When the variable is non-empty, only the listed CIDRs SHALL be able to reach the Kubernetes API server endpoint.

#### Scenario: API server accepts connections from an authorised IP
- **WHEN** `api_server_authorized_ips` contains `203.0.113.0/32` and a kubectl command originates from `203.0.113.0`
- **THEN** the API server SHALL accept the connection (subject to Entra ID authentication)

#### Scenario: API server rejects connections from an unauthorised IP
- **WHEN** `api_server_authorized_ips` does not contain `198.51.100.0/32`
- **THEN** the API server SHALL reject connections from `198.51.100.0` at the network layer

### Requirement: Module outputs for cross-module wiring
The `modules/aks` module SHALL expose outputs that the root module needs to create cross-module role assignments and to pass the OIDC issuer URL to the Key Vault module.

#### Scenario: Required outputs are present after apply
- **WHEN** the aks module is applied
- **THEN** the following outputs SHALL be non-empty: `cluster_id`, `cluster_name`, `oidc_issuer_url`, `kubelet_identity_object_id`, `kubelet_identity_client_id`, `agic_identity_object_id`, `aks_identity_principal_id`
