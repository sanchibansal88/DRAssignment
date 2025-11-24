variable "name" {
  type        = string
  description = "Name prefix for the virtual network."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the network."
}

variable "address_space" {
  type        = string
  description = "CIDR assigned to the VNet."
}

variable "subnet_prefixes" {
  description = "Map of subnet names to CIDR prefixes."
  type        = map(string)
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to network resources."
  default     = {}
}
