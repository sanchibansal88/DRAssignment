resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags
  sku_tier            = "Premium"
  support_plan = "AKSLongTermSupport"

  default_node_pool {
    name                  = "system"
    node_count            = var.node_count
    vm_size               = var.node_size
    vnet_subnet_id        = var.subnet_id
    orchestrator_version  = var.kubernetes_version
    upgrade_settings {
      max_surge = "10%" 
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    dns_service_ip    = "10.2.0.10"
    service_cidr      = "10.2.0.0/24"
    # docker_bridge_cidr = "172.17.0.1/16"
  }
  role_based_access_control_enabled = false
  oidc_issuer_enabled               = false
  local_account_disabled            = false
}
