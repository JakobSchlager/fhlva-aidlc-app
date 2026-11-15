data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

resource "azurerm_container_registry" "main" {
  name                          = local.acr_name
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.main.name
  sku                           = var.sku
  admin_enabled                 = false
  public_network_access_enabled = true
  anonymous_pull_enabled        = false
  zone_redundancy_enabled       = false
  tags                          = var.tags
}
