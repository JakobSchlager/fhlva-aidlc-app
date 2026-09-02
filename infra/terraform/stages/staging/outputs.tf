output "aks_cluster_name" {
  description = "Name of the AKS cluster."
  value       = module.aks.cluster_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the AKS cluster."
  value       = module.aks.oidc_issuer_url
}

output "ingress_public_ip" {
  description = "Public IP address of the Application Gateway ingress."
  value       = module.network.app_gw_public_ip
}
