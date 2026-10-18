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
