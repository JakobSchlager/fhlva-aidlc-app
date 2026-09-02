variable "project_name" {
  type        = string
  description = "Project name prefix for resource names."
}

variable "environment" {
  type        = string
  description = "Deployment environment."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
}

variable "aks_subnet_id" {
  type        = string
  description = "Resource ID of the subnet for AKS node pools."
}

variable "app_gw_id" {
  type        = string
  description = "Resource ID of the Application Gateway for the AGIC addon."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics workspace for Container Insights."
}

variable "api_server_authorized_ips" {
  type        = list(string)
  description = "CIDRs allowed to reach the AKS API server."
}
