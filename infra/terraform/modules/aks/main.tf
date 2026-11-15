data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = "${var.project_name}-${var.environment}-rg"
}

resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = local.identity_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                      = local.cluster_name
  location                  = var.location
  resource_group_name       = data.azurerm_resource_group.main.name
  dns_prefix                = local.dns_prefix
  kubernetes_version        = "1.35"
  local_account_disabled    = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"
  tags                      = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_control_plane.id]
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  default_node_pool {
    name                 = "system"
    vm_size              = var.vm_size
    os_disk_size_gb      = 128
    os_disk_type         = "Managed"
    os_sku               = "AzureLinux"
    auto_scaling_enabled = true
    min_count            = var.min_count
    max_count            = var.max_count
    max_pods             = 110
    vnet_subnet_id       = var.aks_subnet_id

    # Required by the provider to resize the default pool; the rotation does not cordon and drain.
    temporary_name_for_rotation = "tmpsystem"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.1.0.0/16"
    dns_service_ip      = "10.1.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ips
  }

  ingress_application_gateway {
    gateway_id = var.app_gw_id
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }
}
