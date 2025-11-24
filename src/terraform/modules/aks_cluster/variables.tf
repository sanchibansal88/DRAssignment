variable "name" {
  description = "AKS cluster name."
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

variable "dns_prefix" {
  description = "DNS prefix for the public endpoint."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS control plane version."
  type        = string
}

variable "node_count" {
  description = "Agent pool node count."
  type        = number
}

variable "node_size" {
  description = "VM size for the agent nodes."
  type        = string
}

variable "max_surge" {
  description = "Max surge value for node pool upgrades (string, e.g. 33% or 0)."
  type        = string
  default     = "0"
}

variable "subnet_id" {
  description = "Subnet for the cluster agent pool."
  type        = string
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the cluster."
}
