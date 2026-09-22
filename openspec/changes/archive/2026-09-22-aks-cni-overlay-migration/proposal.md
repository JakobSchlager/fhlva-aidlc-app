## Why

The AKS module currently uses Azure CNI standard mode, which requires the control-plane identity to hold `Microsoft.Authorization/roleAssignments/write` on the AKS subnet — a permission not available to the deploying user. Additionally, the AKS subnet (`10.0.1.0/24`, 254 usable IPs) is too small for the configured workload: with `max_pods=110` and up to 5 nodes, standard CNI would demand up to 555 pod IPs from the subnet, causing IP exhaustion before the cluster reaches full capacity.

## What Changes

- **Remove** the `Network Contributor` role assignment on the AKS subnet (`azurerm_role_assignment.aks_subnet_network_contributor`) — no longer needed under overlay mode
- **Switch** the AKS network profile from `network_plugin = "azure"` with `network_policy = "azure"` to `network_plugin_mode = "overlay"` with `network_policy = "cilium"` and `ebpf_data_plane = "cilium"`
- **Add** `pod_cidr = "10.244.0.0/16"` to define the overlay pod address space (invisible to the VNet)
- The AKS control-plane User-Assigned Managed Identity is **retained** — it is still required as the cluster's control-plane identity
- **Update** `scripts/deploy-azure.sh` to read infrastructure outputs (`ACR_LOGIN_SERVER`, `AKS_CLUSTER_NAME`) from `terraform output` rather than a Bicep deployment — the deployment script must work against the now-Terraform-managed infrastructure

## Capabilities

### New Capabilities

_(none — this change modifies an existing capability only)_

### Modified Capabilities

- `terraform-aks`: Networking requirements change from Azure CNI standard (azure network policy, subnet role assignment) to Azure CNI Overlay (Cilium network policy, no subnet role assignment, pod CIDR separate from VNet)

## Impact

- **`infra/terraform/modules/aks/main.tf`**: remove role assignment resource, update `network_profile` block
- **`openspec/specs/terraform-aks/spec.md`**: requirements for control-plane identity role assignment and network profile must be updated
- **`scripts/deploy-azure.sh`**: remove Bicep deployment invocation; replace output capture with `terraform output` calls against `infra/terraform/stages/dev`
- **Existing clusters**: this is a **BREAKING** change for any already-provisioned AKS cluster — switching CNI mode requires cluster recreation (destroy + apply); it cannot be applied in-place
- **AGIC**: continues to work; traffic is routed via NodePort instead of direct pod IPs — no Terraform change required
- **Pod-to-VNet connectivity**: pods in overlay mode cannot be reached directly from other VNet resources using pod IPs; this is acceptable since all ingress flows through AGIC and all egress flows through the node's VNet IP
