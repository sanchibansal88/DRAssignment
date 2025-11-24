locals {
  primary_cluster_name = "${var.project_name}-primary"
  dr_cluster_name      = "${var.project_name}-dr"
  # ACR names must be lowercase alphanumeric (no hyphens), so strip dashes/underscores from the project prefix.
  acr_name             = substr(lower(replace(replace("acr${var.project_name}${random_string.unique.result}", "-", ""), "_", "")), 0, 50)

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

#primary resource group
resource "azurerm_resource_group" "primary" {
  name     = "rg-${var.project_name}-primary"
  location = var.primary_region
  tags     = local.default_tags
}

#dr resource group
resource "azurerm_resource_group" "dr" {
  name     = "rg-${var.project_name}-dr"
  location = var.dr_region
  tags     = local.default_tags
}

module "container_registry" {
  source              = "./modules/acr"
  name                = local.acr_name
  location            = var.primary_region
  resource_group_name = azurerm_resource_group.primary.name
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled
  tags                = local.default_tags
}

module "primary_network" {
  source              = "./modules/network"
  name                = "${var.project_name}-primary"
  location            = var.primary_region
  resource_group_name = azurerm_resource_group.primary.name
  address_space       = var.primary_address_space
  subnet_prefixes = {
    aks = cidrsubnet(var.primary_address_space, 8, 0)
  }
  tags = local.default_tags
}

module "dr_network" {
  source              = "./modules/network"
  name                = "${var.project_name}-dr"
  location            = var.dr_region
  resource_group_name = azurerm_resource_group.dr.name
  address_space       = var.dr_address_space
  subnet_prefixes = {
    aks = cidrsubnet(var.dr_address_space, 8, 0)
  }
  tags = local.default_tags
}

module "primary_aks" {
  source              = "./modules/aks_cluster"
  name                = local.primary_cluster_name
  location            = var.primary_region
  resource_group_name = azurerm_resource_group.primary.name
  dns_prefix          = "${var.project_name}-${random_string.unique.result}-pri"
  kubernetes_version  = var.kubernetes_version
  node_count          = var.aks_node_count
  node_size           = var.aks_node_size
  subnet_id           = module.primary_network.subnet_ids["aks"]
  tags                = local.default_tags
}

module "dr_aks" {
  source              = "./modules/aks_cluster"
  name                = local.dr_cluster_name
  location            = var.dr_region
  resource_group_name = azurerm_resource_group.dr.name
  dns_prefix          = "${var.project_name}-${random_string.unique.result}-dr"
  kubernetes_version  = var.kubernetes_version
  node_count          = var.aks_node_count
  node_size           = var.aks_node_size
  subnet_id           = module.dr_network.subnet_ids["aks"]
  tags                = local.default_tags
}

resource "azurerm_role_assignment" "primary_aks_acr_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.primary_aks.kubelet_identity_object_id
}

resource "azurerm_role_assignment" "dr_aks_acr_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.dr_aks.kubelet_identity_object_id
}

module "primary_postgres" {
  source              = "./modules/postgres"
  name                = "${var.project_name}-pg"
  location            = var.primary_region
  resource_group_name = azurerm_resource_group.primary.name
  admin_user          = var.postgres_admin_user
  admin_password      = var.postgres_admin_password
  sku_name            = "GP_Standard_D2s_v3"
  storage_mb          = 131072
  availability_zone   = "1"
  tags                = local.default_tags
}

module "dr_postgres" {
  source              = "./modules/postgres"
  name                = "${var.project_name}-pg-dr"
  location            = var.dr_region
  resource_group_name = azurerm_resource_group.dr.name
  admin_user          = var.postgres_admin_user
  admin_password      = var.postgres_admin_password
  sku_name            = "GP_Standard_D2s_v3"
  storage_mb          = 131072
  create_mode         = "Replica"
  source_server_id    = module.primary_postgres.server_id
  tags                = local.default_tags
}
