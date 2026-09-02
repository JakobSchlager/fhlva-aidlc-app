locals {
  cluster_name  = "${var.project_name}-${var.environment}-aks"
  identity_name = "${var.project_name}-${var.environment}-aks-identity"
  dns_prefix    = "${var.project_name}-${var.environment}"
}
