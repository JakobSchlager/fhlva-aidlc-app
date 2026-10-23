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

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create the registry in."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
}

variable "sku" {
  type        = string
  description = "The SKU name of the container registry (Basic, Standard, Premium)."
  default     = "Basic"
}

variable "custom_suffix" {
  type        = string
  description = "Optional custom suffix for globally unique naming (e.g. user initials)."
  default     = ""
}

variable "acr_name" {
  type        = string
  description = "Optional explicit name for the Azure Container Registry. If omitted, computed from project_name, environment, and custom_suffix."
  default     = null
}

