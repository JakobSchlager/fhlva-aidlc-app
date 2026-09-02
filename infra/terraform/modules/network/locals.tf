locals {
  vnet_name      = "${var.project_name}-${var.environment}-vnet"
  appgw_name     = "${var.project_name}-${var.environment}-appgw"
  appgw_pip_name = "${var.project_name}-${var.environment}-appgw-pip"
  nsg_name       = "${var.project_name}-${var.environment}-appgw-nsg"
}
