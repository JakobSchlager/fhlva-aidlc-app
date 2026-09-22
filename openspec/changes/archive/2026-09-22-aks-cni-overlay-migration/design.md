## Context

The AKS cluster is provisioned by `infra/terraform/modules/aks/main.tf` and wired into `stages/dev` and `stages/staging` root modules; this change targets the dev stage only. Currently it uses Azure CNI standard mode, where every pod consumes a VNet IP from the AKS subnet (`10.0.1.0/24`). This requires the cluster's control-plane identity to hold `Network Contributor` on the subnet so AKS can manage IP allocation. The deploying principal lacks `Microsoft.Authorization/roleAssignments/write` on the subnet scope, blocking `terraform apply`. Additionally, the subnet has only 254 usable addresses while the cluster can scale to 5 nodes × 110 pods = 550 pod IPs, making IP exhaustion inevitable.

## Goals / Non-Goals

**Goals:**
- Remove the `Network Contributor` role assignment so deployment succeeds with the deploying user's current permissions
- Fix the structural IP exhaustion by moving pod IPs off the VNet subnet
- Switch to Cilium as the network policy engine (required by overlay mode)
- Keep all existing add-ons (AGIC, Container Insights) functional — note: Secrets Store CSI has been removed as part of a parallel migration to Kubernetes-native secret injection (`beer-tracker-secrets` k8s Secret via `envFrom.secretRef`)

**Non-Goals:**
- Changing the node VM size, autoscaling bounds, or Kubernetes version
- Modifying the VNet or subnet CIDRs in the network module
- Adjusting AGIC or Application Gateway configuration
- In-place migration of an already-running cluster (not possible; see Migration Plan)

## Decisions

### Decision 1: Azure CNI Overlay over Kubenet

**Chosen:** Azure CNI Overlay (`network_plugin = "azure"`, `network_plugin_mode = "overlay"`)

**Alternatives considered:**
- *Kubenet*: Simpler, also removes the subnet role assignment, but AGIC does not support Kubenet — ruled out immediately.
- *Azure CNI standard with larger subnet*: Would keep existing architecture, but still requires the role assignment write permission (the original blocker) and would need VNet re-addressing.
- *Azure CNI Overlay*: Removes the role assignment requirement entirely, keeps Azure CNI semantics, is fully supported with AGIC, and is the recommended path for new clusters per Microsoft.

### Decision 2: Cilium as the network policy engine

**Chosen:** `network_policy = "cilium"`

Azure NPM (the current `network_policy = "azure"`) is not compatible with overlay mode — this is not a choice. Cilium eBPF is the only supported network policy engine for Azure CNI Overlay. In AzureRM provider 4.x, setting `network_policy = "cilium"` automatically selects the Cilium eBPF data plane; the previously separate `ebpf_data_plane` attribute was removed from the schema in 4.x. It also offers better performance than NPM (kernel-level eBPF vs. iptables).

### Decision 3: Pod CIDR `10.244.0.0/16`

**Chosen:** `pod_cidr = "10.244.0.0/16"`

This is the Kubernetes default overlay range, not routable in the VNet. It does not overlap with the existing VNet (`10.0.0.0/16`) or the service CIDR (`10.1.0.0/16`). A /16 provides 65 536 addresses — ample headroom for the 5-node cluster.

### Decision 4: Retain the control-plane UAMI

The `azurerm_user_assigned_identity.aks_control_plane` resource is kept. Even without the subnet role assignment, AKS still requires a control-plane identity (`identity.type = "UserAssigned"`). The identity is wired into the cluster's `identity` block and its `principal_id` is exported as `aks_identity_principal_id` for cross-module use.

## Risks / Trade-offs

- **BREAKING — cluster recreation required**: Azure does not support changing the CNI mode on a live cluster. Any deployed cluster must be destroyed and re-created. Workloads will experience downtime during the migration window.
  → *Mitigation*: Plan a maintenance window. Stateful workloads (PostgreSQL) are on a managed service outside the cluster, so data is not at risk. Apply to the dev environment.

- **Pod IPs not reachable from other VNet peers**: In overlay mode, pod IPs (`10.244.x.x`) are invisible outside the cluster. Any VNet-internal client that currently addresses pods directly will break.
  → *Mitigation*: Audit traffic patterns. All inbound traffic in this project flows through AGIC → Service → Pod, and all outbound goes through the node's VNet IP, so this is not a concern for the current workload.

- **AGIC routes via NodePort instead of pod IPs**: Slightly higher latency (one extra hop) compared to direct pod IP routing.
  → *Acceptable*: The delta is negligible for this workload. AGIC supports overlay natively with no configuration change required.

- **Cilium is a new dependency**: Replacing Azure NPM with Cilium introduces a different operational toolchain (`cilium` CLI vs. standard `kubectl` NetworkPolicy debugging).
  → *Mitigation*: Cilium is managed by AKS; no manual installation or upgrade is required. Existing `NetworkPolicy` manifests remain valid (Cilium is a superset).

## Migration Plan

1. Run `terraform destroy` (or target-destroy the AKS module) for the environment being migrated
2. Apply the updated Terraform — cluster re-creates with overlay networking
3. Redeploy application workloads (Helm releases / manifests)
4. Validate ingress through AGIC and secret injection via the `beer-tracker-secrets` Kubernetes Secret

**Rollback:** Revert the `network_profile` changes in Terraform and destroy/recreate the cluster. No infrastructure outside the AKS module is affected.

## Open Questions

- None — the scope is fully defined by the IP exhaustion and permissions constraints.
