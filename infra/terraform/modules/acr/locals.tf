locals {
  clean_suffix     = var.custom_suffix != null ? replace(var.custom_suffix, "/[^a-zA-Z0-9]/", "") : ""
  default_acr_name = lower(replace("${var.project_name}${var.environment}acr${local.clean_suffix}", "/[^a-zA-Z0-9]/", ""))
  acr_name         = var.acr_name != null && var.acr_name != "" ? lower(replace(var.acr_name, "/[^a-zA-Z0-9]/", "")) : local.default_acr_name
}

