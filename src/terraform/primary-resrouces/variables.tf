variable "project_name" {
  description = "Name prefix used for all resources."
  type        = string
  default     = "microservices"
}

variable "environment" {
  description = "Logical environment tag (e.g. dev, prod)."
  type        = string
  default     = "assessment"
}

variable "primary_region" {
  description = "Azure region for the primary deployment."
  type        = string
  default     = "westus3"
}

variable "primary_address_space" {
  description = "CIDR for the primary region virtual network."
  type        = string
  default     = "10.10.0.0/16"
}

variable "aks_node_count" {
  description = "Default number of nodes per AKS node pool."
  type        = number
  default     = 1
}

variable "aks_node_size" {
  description = "VM size for AKS system node pools."
  type        = string
  default     = "Standard_D4ds_v4"
}

variable "kubernetes_version" {
  description = "AKS control plane version."
  type        = string
  default     = "1.30.6"
}

variable "postgres_admin_user" {
  description = "Administrator username for PostgreSQL flexible server."
  type        = string
  default     = "pgadmin"
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL flexible server. Use environment variable TF_VAR_postgres_admin_password or a secrets manager."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    managed-by = "terraform"
  }
}

variable "acr_sku" {
  description = "SKU for the Azure Container Registry."
  type        = string
  default     = "Standard"
}

variable "acr_admin_enabled" {
  description = "Whether to enable the admin user on the Azure Container Registry."
  type        = bool
  default     = false
}
