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

variable "vm_size" {
  type        = string
  description = "VM size for the default node pool."
  default     = "Standard_D2s_v3"
}

variable "min_count" {
  type        = number
  description = "Minimum node count for the default node pool."
  default     = 2
}

variable "max_count" {
  type        = number
  description = "Maximum node count for the default node pool."
  default     = 2
}

variable "custom_suffix" {
  type        = string
  description = "Optional custom suffix to ensure regional uniqueness of the AKS cluster DNS prefix."
  default     = ""
}

variable "dns_prefix" {
  type        = string
  description = "Optional explicit DNS prefix for the AKS cluster. If omitted, computed from project_name, environment, and custom_suffix."
  default     = null
}

