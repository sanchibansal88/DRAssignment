# # output "primary_kube_config" {
# #   description = "Kubeconfig for the primary AKS cluster (certificate-authority-data stripped)."
# #   value       = module.primary_aks.kube_config
# #   sensitive   = true
# # }

# # output "dr_kube_config" {
# #   description = "Kubeconfig for the DR AKS cluster."
# #   value       = module.dr_aks.kube_config
# #   sensitive   = true
# # }

# output "primary_postgres_fqdn" {
#   value       = module.primary_postgres.fqdn
#   description = "FQDN for the primary PostgreSQL flexible server."
# }

# output "dr_postgres_fqdn" {
#   value       = module.dr_postgres.fqdn
#   description = "FQDN for the DR PostgreSQL replica."
# }

# output "primary_aks_id" {
#   value       = module.primary_aks.id
#   description = "Resource ID for the primary AKS cluster."
# }

# output "dr_aks_id" {
#   value       = module.dr_aks.id
#   description = "Resource ID for the DR AKS cluster."
# }

output "container_registry_login_server" {
  value       = module.container_registry.login_server
  description = "Azure Container Registry login server used for container pushes."
}

output "container_registry_name" {
  value       = module.container_registry.name
  description = "Azure Container Registry name (use with az acr login)."
}
