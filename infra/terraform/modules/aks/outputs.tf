output "cluster_id" {
  description = "Resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the AKS cluster for Workload Identity federated credentials."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity."
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "kubelet_identity_client_id" {
  description = "Client ID of the kubelet managed identity."
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id
}

output "agic_identity_object_id" {
  description = "Object ID of the AGIC managed identity created by the ingress_application_gateway addon."
  value       = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

output "aks_identity_principal_id" {
  description = "Principal ID of the AKS control-plane user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_control_plane.principal_id
}
