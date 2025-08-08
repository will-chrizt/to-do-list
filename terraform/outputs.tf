output "frontend_service_url" {
  description = "The external URL for the frontend service."
  value       = kubernetes_service.frontend_service.status[0].load_balancer[0].ingress[0].hostname
}

output "backend_service_cluster_ip" {
  description = "The internal ClusterIP for the backend service."
  value       = kubernetes_service.backend_service.spec[0].cluster_ip
}

output "db_service_cluster_ip" {
  description = "The internal ClusterIP for the database service."
  value       = kubernetes_service.db_service.spec[0].cluster_ip
}
