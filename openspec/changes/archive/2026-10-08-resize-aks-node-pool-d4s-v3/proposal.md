## Why

More memory is needed per node. The single `system` node pool, which also runs the application workloads, uses `Standard_D2s_v3` (2 vCPU, 8 GiB). `Standard_D4s_v3` (4 vCPU, 16 GiB) doubles the memory and CPU per node and stays in the same VM family. The size was chosen by the project owner; measured pod and node memory use (`kubectl top`) was not available when choosing.

## What Changes

- In `infra/terraform/modules/aks/main.tf`, set the `default_node_pool` `vm_size` to `Standard_D4s_v3`.
- Set `temporary_name_for_rotation` on the default node pool. The azurerm provider documents that it must be specified when resizing the default node pool; without it the resize is not accepted as an in-place rotation.
- All other node pool settings (2–5 nodes with autoscaling, `AzureLinux`, 128 GB OS disk, 110 max pods, `max_surge` 33%) stay as they are.
- The `terraform-aks` spec's node-pool requirement is updated to the new VM size.
- No other file in the repository mentions the old size (searched `*.md`, `*.tf`, `*.yaml` outside archived changes).

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `terraform-aks`: the "System node pool with autoscaling" requirement changes its VM size from `Standard_D2s_v3` to `Standard_D4s_v3` and requires a rotation name for resizing.

## Impact

- `infra/terraform/modules/aks/main.tf`: two lines in the `default_node_pool` block.
- `openspec/specs/terraform-aks/spec.md` (through the delta spec).
- Applying rotates the node pool, which disrupts running pods (see design). Needs regional vCPU quota for the `Dsv3` family for old and new nodes at the same time, and increases node cost; no figures are given here because none were looked up.
- Does not touch `infra/terraform/stages/dev/main.tf` or `README.md`, which contain uncommitted edits.
