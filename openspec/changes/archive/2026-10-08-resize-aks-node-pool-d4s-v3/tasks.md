## 1. Pre-checks

- [x] 1.1 Check `Standard_D4s_v3` is available to the subscription in `germanywestcentral` (`az vm list-skus -l germanywestcentral --size Standard_D4s_v3`) and that the regional `Dsv3` vCPU quota covers the largest autoscaled size plus the same number of old nodes during rotation. SKU available with no restrictions (family `standardDSv3Family`, 4 vCPU, 16 GB; output supplied by the project owner, 2026-10-08); `standardDSv3Family` quota: used 0, limit 350 vCPUs (supplied by the project owner, 2026-10-08), enough for 5 old plus 5 new nodes (about 30 vCPUs). Used 0 is unexpected if the cluster runs D2s_v3 nodes: confirm whether the cluster exists in this subscription before assuming a rotation
- [x] 1.2 (Skipped: the cluster is not running, so there is nothing to measure; the memory question stays open) Optional: run `kubectl top nodes` and `kubectl top pods -A` and record whether memory is the constraint (open question in the design)
- [x] 1.3 Decide whether the in-cluster PostgreSQL data may be lost; back it up if not. Decided by the project owner (2026-10-08): the cluster is not running and the PostgreSQL data is disposable, no backup needed

## 2. Terraform

- [x] 2.1 In `infra/terraform/modules/aks/main.tf` change `vm_size` to `"Standard_D4s_v3"` and add `temporary_name_for_rotation = "tmpsystem"` to `default_node_pool`
- [x] 2.2 Run `terraform fmt -check` and `terraform validate` in `infra/terraform/stages/dev/`
- [x] 2.3 Run `terraform plan` and read it (if the cluster is not deployed, expect the cluster to be created with the new size; if it exists but is stopped, expect an in-place pool change): the node pool changes, and `azurerm_kubernetes_cluster.main` is not marked for replacement and nothing is destroyed other than the pool rotation; stop and report otherwise. Result (plan output supplied by the project owner, 2026-10-08): 15 to add, 0 to change, 0 to destroy; the cluster is created (not deployed yet) with `Standard_D4s_v3`, `temporary_name_for_rotation = "tmpsystem"` and 2–5 nodes; no replacement and no destroy

## 3. Apply and verify

- [x] 3.1 Apply in a quiet window and wait for the rotation to finish Applied by the project owner (2026-10-08); apply output not seen
- [x] 3.2 Confirm with `kubectl get nodes -o wide` that nodes are the new size and with `kubectl get pods -A` that all pods run; record the observed downtime. Node size confirmed with `az aks show` (output supplied by the project owner, 2026-10-08): pool `system`, 2 nodes, `Standard_D4s_v3`. `kubectl get nodes` and `kubectl get pods -A` were not run, and no downtime applies because the cluster was newly created, not rotated
- [x] 3.3 Mark anything not run as `VERIFY` in the change notes. Still unverified, kept as VERIFY in design.md: the `tmpsystem` rotation name (not exercised until a later resize), pool rotation on a stopped cluster, pod scheduling on the new nodes, and whether node memory was the actual constraint
