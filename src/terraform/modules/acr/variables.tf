variable "name" {
  description = "Globally unique Azure Container Registry name."
  type        = string
}

variable "location" {
  description = "Azure region for the registry."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that will contain the registry."
  type        = string
}

variable "sku" {
  description = "Container registry SKU (Basic, Standard, Premium)."
  type        = string
  default     = "Standard"
}

variable "admin_enabled" {
  description = "Whether to enable the local admin account."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to the registry."
  type        = map(string)
  default     = {}
}
