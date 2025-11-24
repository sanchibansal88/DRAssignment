locals {
  dr_cluster_name      = "${var.project_name}-dr"
  # ACR names must be lowercase alphanumeric (no hyphens), so strip dashes/underscores from the project prefix.
  acr_name             = substr(lower(replace(replace("acrdr${var.project_name}", "-", ""), "_", "")), 0, 50)

  default_tags = merge(var.tags, {
    project     = var.project_name
    environment = var.environment
  })
}

resource "random_string" "unique" {
  length  = 4
  numeric = false
  upper   = false
  special = false
}

#dr resource group
resource "azurerm_resource_group" "dr" {
  name     = "rg-${var.project_name}-dr"
  location = var.dr_region
  tags     = local.default_tags
}

# module "dr_container_registry" {
#   source              = "./../modules/acr"
#   name                = local.acr_name
#   location            = var.dr_region
#   resource_group_name = azurerm_resource_group.dr.name
#   sku                 = var.acr_sku
#   admin_enabled       = var.acr_admin_enabled
#   tags                = local.default_tags
# }

module "dr_network" {
  source              = "./../modules/network"
  name                = "${var.project_name}-dr"
  location            = var.dr_region
  resource_group_name = azurerm_resource_group.dr.name
  address_space       = var.dr_address_space
  subnet_prefixes = {
    aks = cidrsubnet(var.dr_address_space, 8, 0)
  }
  tags = local.default_tags
}

module "dr_aks" {
  source              = "./../modules/aks_cluster"
  name                = local.dr_cluster_name
  location            = var.dr_region
  resource_group_name = azurerm_resource_group.dr.name
  dns_prefix          = "${var.project_name}-dr"
  kubernetes_version  = var.kubernetes_version
  node_count          = var.aks_node_count
  node_size           = var.aks_node_size
  subnet_id           = module.dr_network.subnet_ids["aks"]
  tags                = local.default_tags
}

resource "azurerm_role_assignment" "dr_aks_acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = module.dr_aks.kubelet_identity_object_id
}

module "dr_postgres" {
  source              = "./../modules/postgres"
  name                = "${var.project_name}-pg-dr"
  location            = var.dr_region
  resource_group_name = azurerm_resource_group.dr.name
  admin_user          = var.postgres_admin_user
  admin_password      = var.postgres_admin_password
  sku_name            = "GP_Standard_D2s_v3"
  storage_mb          = 131072
  create_mode         = "Replica"
  source_server_id    = var.primary_postgres_server_id
  tags                = local.default_tags
}
