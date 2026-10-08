## MODIFIED Requirements

### Requirement: System node pool with autoscaling
The `modules/aks` module SHALL create a single system node pool named `system` with VM size `Standard_D4s_v3`, OS disk size 128 GB, OS disk type `Managed`, OS type `Linux`, OS SKU `AzureLinux`, minimum node count 2, maximum node count 5, max pods per node 110, and max surge upgrade setting of `33%`. The default node pool SHALL set `temporary_name_for_rotation`, so that a later change of VM size rotates the pool instead of being rejected.

#### Scenario: Node pool autoscaling is active within bounds
- **WHEN** the aks module is applied
- **THEN** the system node pool SHALL have `auto_scaling_enabled = true`, `min_count = 2`, and `max_count = 5`

#### Scenario: Node pool uses AzureLinux on Standard_D4s_v3
- **WHEN** the aks module is applied
- **THEN** `vm_size` SHALL be `Standard_D4s_v3` and `os_sku` SHALL be `AzureLinux`

#### Scenario: Rotation name is set for resizing
- **WHEN** the aks module is read
- **THEN** the default node pool SHALL define `temporary_name_for_rotation` with a name different from `system`
