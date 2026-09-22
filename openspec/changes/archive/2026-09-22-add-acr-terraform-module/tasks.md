## 1. Create the ACR Terraform Module

- [x] 1.1 Create `infra/terraform/modules/acr/locals.tf` — define `acr_name` using `lower(replace("${var.project_name}${var.environment}acr", "-", ""))`
- [x] 1.2 Create `infra/terraform/modules/acr/variables.tf` — declare `project_name`, `environment`, `location`, `resource_group_name`, and `tags` variables (all required, no defaults)
- [x] 1.3 Create `infra/terraform/modules/acr/main.tf` — `azurerm_container_registry` resource with `sku = "Standard"`, `admin_enabled = false`, `anonymous_pull_enabled = false`, `public_network_access_enabled = true`, `zone_redundancy_enabled = false`, and a `retention_policy_in_days = 30` / `soft_delete_policy { retention_days = 7 }` block; apply `var.tags`
- [x] 1.4 Create `infra/terraform/modules/acr/outputs.tf` — export `acr_id` (`azurerm_container_registry.main.id`) and `acr_login_server` (`azurerm_container_registry.main.login_server`)

## 2. Update the Dev Stage

- [x] 2.1 Add `module "acr"` block to `infra/terraform/stages/dev/main.tf` with `source = "../../modules/acr"`, passing `project_name`, `environment`, `location`, `resource_group_name = data.azurerm_resource_group.main.name`, and `tags` from `local.*`
- [x] 2.2 Remove the `acr_id = ""` local from `infra/terraform/stages/dev/main.tf`
- [x] 2.3 Replace the `azurerm_role_assignment.kubelet_acr_pull` `for_each` resource with a plain resource: remove the `for_each`, set `scope = module.acr.acr_id` directly, keep `role_definition_name = "AcrPull"` and `principal_id = module.aks.kubelet_identity_object_id`
- [x] 2.4 Add `acr_login_server` output to `infra/terraform/stages/dev/outputs.tf` sourced from `module.acr.acr_login_server`

## 3. Validate Terraform Configuration

- [x] 3.1 Check ACR name availability before applying: `az acr check-name --name fhooeaidlcdevacr` — confirm `nameAvailable: true`
- [x] 3.2 Run `terraform init` in `infra/terraform/stages/dev/` to register the new module
- [x] 3.3 Run `terraform validate` in `infra/terraform/stages/dev/` and confirm no errors
- [x] 3.4 Run `terraform plan` in `infra/terraform/stages/dev/` and confirm the plan shows exactly: 1 resource to create (`azurerm_container_registry.main` via module) + 1 role assignment to create (`azurerm_role_assignment.kubelet_acr_pull`), no unexpected changes to existing resources

## 4. Apply and Verify

- [x] 4.1 Run `terraform apply` in `infra/terraform/stages/dev/`
- [x] 4.2 Confirm `terraform output acr_login_server` returns `fhooeaidlcdevacr.azurecr.io`
- [x] 4.3 Confirm the AcrPull role assignment exists: `az role assignment list --scope $(terraform output -raw acr_id) --query "[].{role:roleDefinitionName, principal:principalName}" -o table` — expect one row with `AcrPull` for the kubelet identity

## 5. Sync the terraform-acr Spec

- [ ] 5.1 Run `openspec sync specs --change "add-acr-terraform-module"` to merge the `terraform-acr` new spec and `terraform-stage-dev` delta into `openspec/specs/`
- [ ] 5.2 Review `openspec/specs/terraform-acr/spec.md` and `openspec/specs/terraform-stage-dev/spec.md` to confirm the merged content is correct
