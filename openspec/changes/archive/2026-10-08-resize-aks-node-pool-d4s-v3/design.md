## Context

`modules/aks` defines one default node pool, `system`: `Standard_D2s_v3`, autoscaling 2–5 nodes, `AzureLinux`, 128 GB managed OS disk, `max_pods = 110`, `max_surge = "33%"`, in the AKS subnet. It carries the application workloads as well as system components; the cluster sets no `zones`. The Helm charts request 512Mi and limit 1Gi of memory per service (for example `charts/auth-service/values.yaml`). The azurerm provider is locked at 4.81.0 (`infra/terraform/.terraform.lock.hcl`).

Provider behaviour, from the 4.81.0 resource documentation (read 2026-10-08 as the raw docs file at the `v4.81.0` tag, through a summarising fetch, so re-read the exact wording when implementing): `vm_size` states that "`temporary_name_for_rotation` must be specified when attempting a resize", and for the pool rotation it says "When cycling the system node pool, it doesn't perform cordon and drain, and it will disrupt rescheduling pods currently running on the previous system node pool."

## Goals / Non-Goals

**Goals:**
- Nodes of `Standard_D4s_v3` in the `system` pool, applied by Terraform without recreating the cluster.

**Non-Goals:**
- Splitting workloads into a separate user node pool.
- Changing autoscaling bounds, OS SKU, disk or networking.
- Tuning pod requests and limits in the Helm charts.

## Decisions

**D1: Resize in place with `temporary_name_for_rotation`, not by editing the pool name or recreating the cluster.**
The provider supports resizing the default pool by creating a temporary pool, moving to it, and recreating the original with the new size. The name must be valid for an AKS node pool and different from `system`; the proposed value is `tmpsystem`. Alternative: recreate the cluster (rejected: destroys the control plane, ingress, state in the cluster and the role assignments tied to it).

**D2: Choose `Standard_D4s_v3`, as the project owner decided.**
Same family as the current size, so existing quota for the `Dsv3` family is the most likely place to find room (not verified). Memory-optimised sizes (for example `E2s_v3`, 2 vCPU / 16 GiB) were the alternative that doubles only memory; not chosen.

**D3: Leave autoscaling bounds (2–5) unchanged.**
Doubling the node size roughly doubles the cluster's maximum capacity; revisit if cost matters.

## Risks / Trade-offs

- [The rotation does not cordon and drain] → Pods on the old pool are disrupted and rescheduled. Run it in a quiet window and expect brief unavailability; check afterwards with `kubectl get pods -A`. The actual duration is not measured.
- [Quota for the `Dsv3` family in `germanywestcentral` may not cover old and new nodes at once] → Checked 2026-10-08 (output supplied by the project owner): `standardDSv3Family` limit 350 vCPUs, used 0, which covers the worst case of about 30 vCPUs. "Used 0" is unexpected if the cluster already runs D2s_v3 nodes, so whether the cluster exists in this subscription is to be confirmed; the total regional vCPU limit was not checked.
- [The `Standard_D4s_v3` SKU may be restricted or unavailable in the region or subscription] → Checked 2026-10-08 with `az vm list-skus -l germanywestcentral --size Standard_D4s_v3` (output supplied by the project owner): available, no restrictions, family `standardDSv3Family`, 4 vCPU / 16 GB.
- [In-cluster PostgreSQL (Bitnami, with a persistent volume) is rescheduled onto a new node] → An Azure disk volume must detach and reattach; whether this goes smoothly with this cluster (no zones set) is not verified. VERIFY, and take a backup or confirm data loss is acceptable before applying.
- [Higher node cost] → D4s_v3 nodes cost more than D2s_v3; no figures were looked up. Compare with the Azure pricing page before applying.
- [The plan could show the cluster being replaced] → Read `terraform plan` before applying and stop if `azurerm_kubernetes_cluster.main` is marked for replacement.
- [The rotation name length or character rules] → AKS restricts node pool names; `tmpsystem` is believed valid (lowercase alphanumeric, short). VERIFY with the plan or apply.

## Migration Plan

1. Confirm quota and SKU availability; check the plan shows an in-place update (or the documented pool rotation), not a cluster replacement.
2. Apply in a quiet window; wait until the rotation finishes.
3. Verify with `kubectl get nodes -o wide` (new size) and `kubectl get pods -A` (all running).
4. Rollback: set `vm_size` back to `Standard_D2s_v3` and apply, which causes a second rotation.

## Update 2026-10-08

The project owner states the cluster is not running and the in-cluster PostgreSQL data is disposable. If the cluster is not deployed, applying creates it directly at the new size: there is no rotation, so the pod-disruption and volume-reattach risks above do not apply, and `temporary_name_for_rotation` only matters for later resizes. If "not running" means a stopped cluster, the plan is expected to show an in-place change; how a stopped cluster handles the pool rotation was not checked (VERIFY). `terraform plan` shows which case it is. Result: the plan (output supplied by the project owner, 2026-10-08) shows 15 resources to add, 0 to change, 0 to destroy, including the cluster, so it is the not-deployed case: the cluster is created at `Standard_D4s_v3` and no rotation takes place. The rotation name `tmpsystem` is not exercised until a later resize (VERIFY then). After the apply, `az aks show` reported the `system` pool with 2 nodes of `Standard_D4s_v3` (output supplied by the project owner, 2026-10-08).

## Open Questions

- Is memory the actual constraint? `kubectl top nodes` and `kubectl top pods -A` were not run, and `kubectl describe node` allocatable memory was not checked. A different bottleneck (for example PostgreSQL's own limits) would not be fixed by bigger nodes.
- Is the in-cluster PostgreSQL data disposable, so a failed reattach is acceptable?
- Should the autoscaling maximum change with the larger node size?
