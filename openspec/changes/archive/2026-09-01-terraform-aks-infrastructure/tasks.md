## 1. Bootstrap and Root Scaffold

- [x] 1.1 Create `infra/terraform/` directory tree: root files and `modules/network`, `modules/aks`, `modules/keyvault` subdirectories
- [x] 1.2 Write `infra/terraform/providers.tf` — declare `required_providers` for `hashicorp/azurerm ~> 4.0` and `hashicorp/azuread ~> 3.0`; add `provider "azurerm"` block with `subscription_id` variable and `features {}`
- [x] 1.3 Write `infra/terraform/backend.tf` — configure `azurerm` backend with `resource_group_name`, `storage_account_name`, `container_name`, `key` placeholders (values supplied via `-backend-config` at init time)
- [x] 1.4 Write `infra/terraform/variables.tf` — root-level variables: `project_name`, `environment`, `location`, `subscription_id`, `ingress_allowed_ips`, `api_server_authorized_ips`, `alert_email_address`, and all six sensitive secret variables (`auth_rs256_private_key`, `auth_db_password`, `tracking_db_password`, `notifications_db_password`, `statistics_db_password`, `internal_api_key`)
- [x] 1.5 Write `infra/terraform/locals.tf` — shared `tags` map (`project`, `environment`, `managed_by = "terraform"`) and any root-level name computations
- [x] 1.6 Write `infra/terraform/dev.tfvars` — non-secret values for dev: `project_name = "beertracker"`, `environment = "dev"`, `location = "germanywestcentral"`, placeholder CIDRs for `ingress_allowed_ips` and `api_server_authorized_ips`
- [x] 1.7 Write `infra/terraform/staging.tfvars` — same structure as `dev.tfvars` for the staging environment
- [x] 1.8 Add `infra/terraform/*.auto.tfvars` and `infra/terraform/*.tfvars` secret files to `.gitignore` (keep `dev.tfvars` and `staging.tfvars` tracked)

## 2. Network Module

- [x] 2.1 Write `modules/network/variables.tf` — inputs: `project_name`, `environment`, `location`, `tags`, `ingress_allowed_ips`
- [x] 2.2 Write `modules/network/locals.tf` — resource names: `vnet_name`, `appgw_name`, `appgw_pip_name`, `nsg_name`
- [x] 2.3 Write `modules/network/main.tf` — `azurerm_virtual_network` with address space `10.0.0.0/16` and three subnets (aks `10.0.1.0/24`, appgw `10.0.2.0/24`, postgres `10.0.3.0/24` with `Microsoft.DBforPostgreSQL/flexibleServers` delegation)
- [x] 2.4 Add `azurerm_public_ip` (Standard SKU, Static) and `azurerm_application_gateway` (Standard_v2, autoscale 1–10, placeholder routing rule on port 80) to `modules/network/main.tf`
- [x] 2.5 Add `azurerm_network_security_group` with allow rules for TCP 80 and 443 from `ingress_allowed_ips` and a lower-priority deny rule for the same ports from `Internet`; associate it with `appgw-subnet` via `azurerm_subnet_network_security_group_association`
- [x] 2.6 Write `modules/network/outputs.tf` — `vnet_id`, `vnet_name`, `aks_subnet_id`, `appgw_subnet_id`, `postgres_subnet_id`, `app_gw_id`, `app_gw_name`, `app_gw_public_ip`

## 3. AKS Module

- [x] 3.1 Write `modules/aks/variables.tf` — inputs: `project_name`, `environment`, `location`, `tags`, `aks_subnet_id`, `app_gw_id`, `log_analytics_workspace_id`, `api_server_authorized_ips`
- [x] 3.2 Write `modules/aks/locals.tf` — `cluster_name`, `identity_name`, `network_contributor_role_id`, `dns_prefix`
- [x] 3.3 Write `modules/aks/main.tf` — `azurerm_user_assigned_identity` for the control plane; `azurerm_role_assignment` granting it `Network Contributor` on `aks_subnet_id`
- [x] 3.4 Add `azurerm_kubernetes_cluster` resource to `modules/aks/main.tf` with: user-assigned identity, `dns_prefix`, `kubernetes_version = "1.30"`, `azure_active_directory_role_based_access_control` block (managed, azure_rbac_enabled), `disable_local_accounts = true`, OIDC issuer and Workload Identity enabled, auto-upgrade `patch` / `NodeImage`
- [x] 3.5 Add `default_node_pool` block to the AKS cluster: name `system`, `vm_size = "Standard_D2s_v3"`, `os_disk_size_gb = 128`, `os_disk_type = "Managed"`, `os_sku = "AzureLinux"`, `enable_auto_scaling = true`, `min_count = 2`, `max_count = 5`, `max_pods = 110`, `vnet_subnet_id`, upgrade settings `max_surge = "33%"`
- [x] 3.6 Add `network_profile` block: `network_plugin = "azure"`, `network_policy = "azure"`, `service_cidr = "10.1.0.0/16"`, `dns_service_ip = "10.1.0.10"`, `load_balancer_sku = "standard"`, `outbound_type = "loadBalancer"`
- [x] 3.7 Add `api_server_access_profile` block with `authorized_ip_ranges = var.api_server_authorized_ips`
- [x] 3.8 Add `ingress_application_gateway` addon block referencing `var.app_gw_id`
- [x] 3.9 Add `oms_agent` addon block with `log_analytics_workspace_id` and `msi_auth_for_monitoring_enabled = true`
- [x] 3.10 Add `key_vault_secrets_provider` addon block with `secret_rotation_enabled = true` and `secret_rotation_interval = "2m"`
- [x] 3.11 Write `modules/aks/outputs.tf` — `cluster_id`, `cluster_name`, `oidc_issuer_url`, `kubelet_identity_object_id`, `kubelet_identity_client_id`, `agic_identity_object_id`, `aks_identity_principal_id`

## 4. Key Vault Module

- [x] 4.1 Write `modules/keyvault/variables.tf` — inputs: `project_name`, `environment`, `location`, `tags`, `oidc_issuer_url`, `k8s_namespace` (default `"beer-tracker"`), six `sensitive` secret variables
- [x] 4.2 Write `modules/keyvault/locals.tf` — `kv_name`, `services` list (name + sa_name pairs for all four services), `kv_secrets_user_role_id`
- [x] 4.3 Write `modules/keyvault/main.tf` — `azurerm_key_vault` with standard SKU, `enable_rbac_authorization = true`, soft-delete 90 days, purge protection enabled, `public_network_access_enabled = true`, network ACLs default Allow / bypass AzureServices
- [x] 4.4 Add `azurerm_user_assigned_identity` resources (one per service, using `for_each` over the services map) to `modules/keyvault/main.tf`
- [x] 4.5 Add `azurerm_role_assignment` for Key Vault Secrets User on the vault for each service identity (using `for_each`)
- [x] 4.6 Add `azurerm_federated_identity_credential` for each service UAMI binding to `system:serviceaccount:<k8s_namespace>:<service-name>` with issuer from `var.oidc_issuer_url` and audience `api://AzureADTokenExchange`
- [x] 4.7 Add `azurerm_key_vault_secret` resources for all six secrets (`auth-rs256-private-key`, `auth-db-password`, `tracking-db-password`, `notifications-db-password`, `statistics-db-password`, `internal-api-key`) with `content_type = "text/plain"` and `lifecycle { ignore_changes = [value] }` to prevent drift from out-of-band rotation
- [x] 4.8 Write `modules/keyvault/outputs.tf` — `key_vault_name`, `key_vault_uri`, `key_vault_id`, `auth_service_client_id`, `beer_tracking_service_client_id`, `health_notification_service_client_id`, `statistics_service_client_id`

## 5. Root Module Wiring

- [x] 5.1 Write `infra/terraform/main.tf` — call `module "network"`, `module "aks"`, `module "keyvault"` passing outputs between modules (e.g. `aks_subnet_id = module.network.aks_subnet_id`, `oidc_issuer_url = module.aks.oidc_issuer_url`)
- [x] 5.2 Add `azurerm_role_assignment` for AGIC identity → `Contributor` on the Application Gateway (uses `module.network.app_gw_id` and `module.aks.agic_identity_object_id`)
- [x] 5.3 Add `azurerm_role_assignment` placeholder for kubelet identity → `AcrPull` on ACR (commented out / behind a `var.acr_id != ""` condition; ACR module not yet in scope)
- [x] 5.4 Write `infra/terraform/outputs.tf` — `acr_login_server` (placeholder), `aks_cluster_name`, `oidc_issuer_url`, `key_vault_name`, `key_vault_uri`, `ingress_public_ip`, `service_identity_client_ids` object

## 6. Validation and Documentation

- [x] 6.1 Run `terraform fmt -recursive infra/terraform/` and fix any formatting issues
- [x] 6.2 Run `terraform validate` in `infra/terraform/` (requires `terraform init` with a backend config file; use `-backend=false` for offline validation)
- [x] 6.3 Write `infra/terraform/README.md` documenting: prerequisites, bootstrap steps (storage account creation), init command with `-backend-config`, apply command with `-var-file`, and secret injection via `TF_VAR_*` environment variables
- [x] 6.4 Write `scripts/bootstrap-tf-state.sh` — `az` CLI script to create the resource group, storage account (with soft-delete and versioning enabled), and blob container used as the Terraform backend
