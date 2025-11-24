resource "azurerm_postgresql_flexible_server" "this" {
  name                   = var.name
  location               = var.location
  resource_group_name    = var.resource_group_name
  administrator_login    = var.admin_user
  administrator_password = var.admin_password
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  version                = var.pg_version
  zone                   = var.availability_zone
  backup_retention_days  = 7
  geo_redundant_backup_enabled = false
  dynamic "high_availability" {
    for_each = var.create_mode == "Replica" ? [] : [1]
    content {
      mode = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  create_mode      = var.create_mode
  source_server_id = var.create_mode == "Replica" ? var.source_server_id : null
  tags             = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# resource "azurerm_postgresql_flexible_server_database" "appdb" {
#   name      = "appdb"
#   server_id = azurerm_postgresql_flexible_server.this.id
#   charset   = "UTF8"
#   collation = "en_US.utf8"
# }

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_internal" {
  name             = "allow-azure"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# resource "azurerm_postgresql_flexible_server_configuration" "wal_level" {
#   name      = "wal_level"
#   server_id = azurerm_postgresql_flexible_server.this.id
#   value     = "logical"
# }

# resource "azurerm_postgresql_flexible_server_configuration" "max_wal_senders" {
#   name      = "max_wal_senders"
#   server_id = azurerm_postgresql_flexible_server.this.id
#   value     = "10"
# }
