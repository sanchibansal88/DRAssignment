variable "name" {
  description = "PostgreSQL server name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "admin_user" {
  description = "Administrator username."
  type        = string
}

variable "admin_password" {
  description = "Administrator password."
  type        = string
  sensitive   = true
}

variable "sku_name" {
  description = "PostgreSQL SKU (e.g. GP_Standard_D4s_v3)."
  type        = string
}

variable "storage_mb" {
  description = "Storage in MB."
  type        = number
}

variable "pg_version" {
  description = "PostgreSQL version."
  type        = string
  default     = "15"
}

variable "availability_zone" {
  description = "Availability zone."
  type        = string
  default     = "1"
}

variable "create_mode" {
  description = "Creation mode for the server (Default or Replica)."
  type        = string
  default     = "Default"
}

variable "source_server_id" {
  description = "If create_mode=Replica, reference to the primary server ID."
  type        = string
  default     = null
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the server."
}
