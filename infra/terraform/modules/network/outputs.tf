output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet."
  value       = azurerm_subnet.aks.id
}

output "appgw_subnet_id" {
  description = "Resource ID of the Application Gateway subnet."
  value       = azurerm_subnet.appgw.id
}

output "postgres_subnet_id" {
  description = "Resource ID of the PostgreSQL subnet."
  value       = azurerm_subnet.postgres.id
}

output "app_gw_id" {
  description = "Resource ID of the Application Gateway."
  value       = azurerm_application_gateway.main.id
}

output "app_gw_name" {
  description = "Name of the Application Gateway."
  value       = azurerm_application_gateway.main.name
}

output "app_gw_public_ip" {
  description = "Public IP address of the Application Gateway."
  value       = azurerm_public_ip.appgw.ip_address
}
