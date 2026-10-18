locals {
  subscription_id = var.subscription_id != null && var.subscription_id != "" ? var.subscription_id : "FILL_IN_STAGING_SUBSCRIPTION_ID"

  project_name = var.project_name
  environment  = var.environment
  location     = var.location

  ingress_allowed_ips       = var.ingress_allowed_ips
  api_server_authorized_ips = var.api_server_authorized_ips

  alert_email_address          = var.alert_email_address
  aks_cluster_admin_object_ids = var.aks_cluster_admin_object_ids

  tags = {
    project     = local.project_name
    environment = local.environment
    managed_by  = "terraform"
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = "${local.project_name}-${local.environment}-rg"
}

data "azurerm_log_analytics_workspace" "main" {
  name                = "${local.project_name}-${local.environment}-law"
  resource_group_name = data.azurerm_resource_group.main.name
}

module "network" {
  source = "../../modules/network"

  project_name        = local.project_name
  environment         = local.environment
  location            = local.location
  tags                = local.tags
  ingress_allowed_ips = local.ingress_allowed_ips
}

module "aks" {
  source = "../../modules/aks"

  project_name               = local.project_name
  environment                = local.environment
  location                   = local.location
  tags                       = local.tags
  aks_subnet_id              = module.network.aks_subnet_id
  app_gw_id                  = module.network.app_gw_id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.main.id
  api_server_authorized_ips  = local.api_server_authorized_ips
  vm_size                    = var.aks_vm_size
  min_count                  = var.aks_min_count
  max_count                  = var.aks_max_count
}

module "acr" {
  source = "../../modules/acr"

  project_name        = local.project_name
  environment         = local.environment
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "agic_appgw_contributor" {
  scope                = module.network.app_gw_id
  role_definition_name = "Contributor"
  principal_id         = module.aks.agic_identity_object_id
}

resource "azurerm_role_assignment" "agic_vnet_network_contributor" {
  scope                = module.network.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.aks.agic_identity_object_id
}

resource "azurerm_role_assignment" "agic_rg_reader" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = module.aks.agic_identity_object_id
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = module.acr.acr_id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

resource "azurerm_role_assignment" "aks_cluster_admin" {
  for_each = toset(local.aks_cluster_admin_object_ids)

  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}
