locals {
  clean_suffix       = var.custom_suffix != null && var.custom_suffix != "" ? "-${replace(var.custom_suffix, "/[^a-zA-Z0-9-]/", "")}" : ""
  default_dns_prefix = "${var.project_name}-${var.environment}${local.clean_suffix}"
  cluster_name       = "${var.project_name}-${var.environment}-aks"
  identity_name      = "${var.project_name}-${var.environment}-aks-identity"
  dns_prefix         = var.dns_prefix != null && var.dns_prefix != "" ? var.dns_prefix : local.default_dns_prefix
}

