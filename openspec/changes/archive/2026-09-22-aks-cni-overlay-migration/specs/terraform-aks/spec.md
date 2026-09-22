## MODIFIED Requirements

### Requirement: AKS control-plane managed identity
The `modules/aks` module SHALL create a User-Assigned Managed Identity for the AKS control plane. The AKS cluster SHALL use this identity as its control-plane identity (`identity.type = "UserAssigned"`). No role assignment on the AKS subnet is required or created — overlay mode does not require the control-plane identity to manage VNet IP allocations.

#### Scenario: Control-plane identity exists
- **WHEN** the aks module is applied with `aks_subnet_id` provided
- **THEN** a UAMI named `<project>-<env>-aks-identity` SHALL exist and SHALL be set as the cluster control-plane identity

#### Scenario: No Network Contributor role assignment exists on the AKS subnet
- **WHEN** the aks module is applied
- **THEN** no `Microsoft.Authorization/roleAssignments` SHALL be created on the AKS subnet scoped to the control-plane identity

### Requirement: AKS cluster provisioning
The `modules/aks` module SHALL create a managed AKS cluster with the following fixed configuration: Kubernetes version `1.35`, Azure RBAC enabled, local accounts disabled, Entra ID managed integration with `enableAzureRBAC: true`, Azure CNI Overlay network plugin (`network_plugin = "azure"`, `network_plugin_mode = "overlay"`) with Cilium network policy (`network_policy = "cilium"`, `network_data_plane = "cilium"`), pod CIDR `10.244.0.0/16`, service CIDR `10.1.0.0/16`, DNS service IP `10.1.0.10`, and standard load balancer with `loadBalancer` outbound type. The cluster SHALL use the AKS subnet passed as `var.aks_subnet_id` for node IPs only; pod IPs SHALL be allocated from the overlay pod CIDR and SHALL NOT consume addresses from the VNet subnet.

#### Scenario: Cluster exists with correct Kubernetes version
- **WHEN** the aks module is applied
- **THEN** a cluster named `<project>-<env>-aks` SHALL exist running Kubernetes `1.35`

#### Scenario: Local accounts are disabled and Azure RBAC is active
- **WHEN** the aks module is applied
- **THEN** `local_account_disabled` SHALL be `true` and the AAD profile SHALL have `azure_rbac_enabled = true`

#### Scenario: Azure CNI Overlay networking is configured with Cilium
- **WHEN** the aks module is applied
- **THEN** the network profile SHALL use `network_plugin = "azure"`, `network_plugin_mode = "overlay"`, `network_policy = "cilium"`, `network_data_plane = "cilium"`, and `pod_cidr = "10.244.0.0/16"`

#### Scenario: Pod IPs do not consume VNet subnet addresses
- **WHEN** the aks module is applied and pods are scheduled
- **THEN** running pod IPs SHALL fall within `10.244.0.0/16` and SHALL NOT fall within the AKS subnet range (`10.0.1.0/24`)
