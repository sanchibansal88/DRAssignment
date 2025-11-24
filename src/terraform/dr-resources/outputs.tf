output "dr_kube_config" {
  description = "Kubeconfig for the dr AKS cluster (certificate-authority-data stripped)."
  value       = module.dr_aks.kube_config
  sensitive   = true
}


# output "dr_postgres_fqdn" {
#   value       = module.dr_postgres.fqdn
#   description = "FQDN for the dr PostgreSQL flexible server."
# }


output "dr_aks_id" {
  value       = module.dr_aks.id
  description = "Resource ID for the dr AKS cluster."
}



# output "container_registry_login_server" {
#   value       = module.dr_container_registry.login_server
#   description = "Azure Container Registry login server used for container pushes."
# }

# output "container_registry_name" {
#   value       = module.dr_container_registry.name
#   description = "Azure Container Registry name (use with az acr login)."
# }
