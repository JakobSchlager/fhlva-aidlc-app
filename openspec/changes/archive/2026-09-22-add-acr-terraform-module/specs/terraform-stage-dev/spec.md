## MODIFIED Requirements

### Requirement: Dev stage calls all root modules
The dev stage `main.tf` SHALL call the `network`, `aks`, `keyvault`, and `acr` modules using relative paths (`../../modules/<name>`), passing values from `local.*` rather than `var.*`. The `acr` module SHALL receive `resource_group_name` from `data.azurerm_resource_group.main.name`. The `kubelet_acr_pull` role assignment SHALL reference `module.acr.acr_id` as its scope; the empty `acr_id = ""` local placeholder SHALL be removed.

#### Scenario: Module sources use relative paths
- **WHEN** the dev stage `main.tf` is read
- **THEN** each module block (`network`, `aks`, `keyvault`, `acr`) SHALL have `source = "../../modules/<name>"` and all required inputs SHALL reference `local.*` values

#### Scenario: Kubelet identity gets AcrPull on the ACR
- **WHEN** the dev stage is applied
- **THEN** a role assignment of `AcrPull` SHALL exist on the ACR resource scoped to the kubelet managed identity (`module.aks.kubelet_identity_object_id`)

## ADDED Requirements

### Requirement: Dev stage exposes ACR login server output
The dev stage `outputs.tf` SHALL expose `acr_login_server` sourced from `module.acr.acr_login_server`, so deploy scripts can discover the registry endpoint from Terraform output without hardcoding.

#### Scenario: ACR login server is available as a Terraform output
- **WHEN** `terraform output acr_login_server` is run in `infra/terraform/stages/dev/`
- **THEN** it SHALL return the FQDN of the provisioned container registry (e.g. `fhooeaidlcdevacr.azurecr.io`)
