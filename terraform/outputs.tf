output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks.name
}

output "eks_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.eks.endpoint
}

output "frontend_lb_hostname" {
  description = "Frontend LoadBalancer hostname (may take a few minutes)"
  value       = kubernetes_service.frontend.status[0].load_balancer[0].ingress[0].hostname
  depends_on  = [kubernetes_service.frontend]
}

output "backend_service_name" {
  description = "Kubernetes backend service name"
  value       = kubernetes_service.backend.metadata[0].name
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint"
  value       = aws_db_instance.postgres.address
}

output "ecr_backend_repo" {
  description = "ECR backend repository URI"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repo" {
  description = "ECR frontend repository URI"
  value       = aws_ecr_repository.frontend.repository_url
}
