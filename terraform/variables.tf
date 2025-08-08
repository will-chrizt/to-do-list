variable "aws_region" {
  description = "The AWS region where the EKS cluster is located."
  type        = string
  default     = "us-west-2" # Change to your desired region
}

variable "eks_cluster_name" {
  description = "The name of your existing EKS cluster."
  type        = string
}

variable "ecr_registry_url" {
  description = "The URL of your ECR registry (e.g., 123456789012.dkr.ecr.us-west-2.amazonaws.com)."
  type        = string
}

variable "ecr_repo_backend" {
  description = "The name of the ECR repository for the backend image."
  type        = string
}

variable "ecr_repo_frontend" {
  description = "The name of the ECR repository for the frontend image."
  type        = string
}

variable "image_tag" {
  description = "The Docker image tag to deploy (e.g., latest or a commit hash)."
  type        = string
  default     = "latest"
}

variable "db_name" {
  description = "The name of the PostgreSQL database."
  type        = string
  default     = "todo_db"
}

variable "db_username" {
  description = "The username for the PostgreSQL database."
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "The password for the PostgreSQL database."
  type        = string
  default     = "password" # IMPORTANT: Change this to a strong, secret password in production!
}
