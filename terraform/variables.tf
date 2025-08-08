variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "my-eks-cluster"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "ecr_repo_backend" {
  description = "Name for backend ECR repo"
  type        = string
  default     = "my-backend"
}

variable "ecr_repo_frontend" {
  description = "Name for frontend ECR repo"
  type        = string
  default     = "my-frontend"
}

variable "image_tag" {
  description = "Image tag for deployments"
  type        = string
  default     = "latest"
}

variable "db_name" {
  description = "Postgres DB name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Postgres username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Postgres password (change!)"
  type        = string
  default     = "password123"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage (GB)"
  type        = number
  default     = 20
}

variable "public_access_cidrs_for_rds" {
  description = "CIDRs allowed to reach RDS (for demo; tighten in production)"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}
