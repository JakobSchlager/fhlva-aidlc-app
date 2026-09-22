locals {
  acr_name = lower(replace("${var.project_name}${var.environment}acr", "-", ""))
}
