variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
  default     = ""
}

variable "project_name" {
  type        = string
  description = "Project name prefix."
  default     = "fhooe-aidlc"
}

variable "environment" {
  type        = string
  description = "Deployment environment."
  default     = "dev"
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "germanywestcentral"
}

variable "alert_email_address" {
  type        = string
  description = "Email address for monitoring alerts."
  default     = "platform@example.com"
}

variable "aks_cluster_admin_object_ids" {
  type        = list(string)
  description = "Entra ID object IDs granted AKS RBAC Cluster Admin role."
  default     = []
}

variable "ingress_allowed_ips" {
  type        = list(string)
  description = "CIDR ranges allowed to access Application Gateway ingress."
  default     = [
    "78.104.0.0/16",
    "185.154.40.0/22",
    "193.170.0.0/15"
  ]
}

variable "api_server_authorized_ips" {
  type        = list(string)
  description = "CIDR ranges allowed to access the AKS API server."
  default     = [
    "78.104.0.0/16",
    "185.154.40.0/22",
    "193.170.0.0/15"
  ]
}

variable "aks_vm_size" {
  type        = string
  description = "VM size for the AKS default system node pool."
  default     = "Standard_D2s_v3"
}

variable "aks_min_count" {
  type        = number
  description = "Minimum node count for AKS default system node pool."
  default     = 2
}

variable "aks_max_count" {
  type        = number
  description = "Maximum node count for AKS default system node pool."
  default     = 2
}
