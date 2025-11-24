output "id" {
  value       = azurerm_kubernetes_cluster.this.id
  description = "Resource ID for the AKS cluster."
}

output "name" {
  value       = azurerm_kubernetes_cluster.this.name
  description = "AKS cluster name."
}

output "kubelet_identity_object_id" {
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  description = "Managed identity object ID used by the kubelet (for pulling from ACR)."
}

output "kube_config" {
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  description = "Kubeconfig for the AKS cluster."
  sensitive   = true
}
