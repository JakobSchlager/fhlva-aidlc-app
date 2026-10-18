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

variable "ingress_allowed_ips" {
  type        = list(string)
  description = "CIDRs allowed to reach the Application Gateway on ports 80 and 443."
}

variable "min_capacity" {
  type        = number
  description = "Minimum capacity for Application Gateway autoscaling."
  default     = 0
}

variable "max_capacity" {
  type        = number
  description = "Maximum capacity for Application Gateway autoscaling."
  default     = 2
}
