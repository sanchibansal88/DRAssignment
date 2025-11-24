output "id" {
  value       = azurerm_container_registry.this.id
  description = "Resource ID for the container registry."
}

output "name" {
  value       = azurerm_container_registry.this.name
  description = "Name of the container registry."
}

output "login_server" {
  value       = azurerm_container_registry.this.login_server
  description = "Registry login server (hostname)."
}
