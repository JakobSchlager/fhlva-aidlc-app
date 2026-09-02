locals {
  subscription_id = "FILL_IN_STAGING_SUBSCRIPTION_ID"

  project_name = "fhooe-aidlc"
  environment  = "staging"
  location     = "germanywestcentral"

  ingress_allowed_ips = [
    "0.0.0.0/0",
  ]

  api_server_authorized_ips = [
    "0.0.0.0/0",
  ]

  alert_email_address = "platform@example.com"

  acr_id = "" # set to ACR resource ID once ACR module is added

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

resource "azurerm_role_assignment" "agic_appgw_contributor" {
  scope                = module.network.app_gw_id
  role_definition_name = "Contributor"
  principal_id         = module.aks.agic_identity_object_id
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  for_each = local.acr_id != "" ? toset([local.acr_id]) : toset([])

  scope                = each.value
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}
