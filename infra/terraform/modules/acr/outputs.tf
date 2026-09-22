output "acr_id" {
  description = "Resource ID of the Azure Container Registry."
  value       = azurerm_container_registry.main.id
}

output "acr_login_server" {
  description = "Login server FQDN of the Azure Container Registry."
  value       = azurerm_container_registry.main.login_server
}
