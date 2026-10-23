locals {
  subscription_id = "34cf92aa-0a2f-47dc-a8ac-d96a5aa5256d"

  project_name = "fhooe-aidlc"
  environment  = "dev"
  location     = "polandcentral"

  # initially defined to ACONET network ranges
  ingress_allowed_ips = [
    "78.104.0.0/16",
    "185.154.40.0/22",
    "193.170.0.0/15",
  ]

  # initially defined to ACONET network ranges
  api_server_authorized_ips = [
    "78.104.0.0/16",
    "185.154.40.0/22",
    "193.170.0.0/15",
  ]

  # TODO: change to valid email address
  alert_email_address = "platform@example.com"

  # TODO: enter object user ids
  # Entra ID object IDs of the users who may administer the AKS cluster with kubectl
  # (role: Azure Kubernetes Service RBAC Cluster Admin). Find yours with:
  #   az ad signed-in-user show --query id -o tsv
  aks_cluster_admin_object_ids = ["35ba35a9-8ce0-4765-b176-776630a58d63"]

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
