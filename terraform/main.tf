# Configure the AWS provider
provider "aws" {
  region = var.aws_region
}

# Data source to retrieve existing EKS cluster details
data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

# Data source to retrieve authentication token for the EKS cluster
data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

# Configure the Kubernetes provider to connect to the EKS cluster
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# -----------------------------------------------------------------------------
# Kubernetes Secret for Database Credentials
# This securely stores the database URL for the backend to use.
# Note: In a real-world scenario, avoid hardcoding passwords directly.
# Use AWS Secrets Manager or another secret management solution.
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "db_credentials" {
  metadata {
    name = "db-credentials"
  }
  data = {
    database_url = base64encode("postgresql://${var.db_username}:${var.db_password}@${kubernetes_service.db_service.metadata[0].name}:5432/${var.db_name}")
  }
  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Kubernetes Persistent Volume Claim for PostgreSQL Database
# This requests persistent storage for the database data.
# -----------------------------------------------------------------------------
resource "kubernetes_persistent_volume_claim" "db_pvc" {
  metadata {
    name = "db-pvc"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Deployment for PostgreSQL Database
# Deploys a single replica of the PostgreSQL container.
# -----------------------------------------------------------------------------
resource "kubernetes_deployment" "db_deployment" {
  metadata {
    name = "db-deployment"
    labels = {
      app = "db"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "db"
      }
    }
    template {
      metadata {
        labels = {
          app = "db"
        }
      }
      spec {
        container {
          name  = "db-container"
          image = "postgres:13" # Using a standard PostgreSQL image
          port {
            container_port = 5432
          }
          env {
            name  = "POSTGRES_DB"
            value = var.db_name
          }
          env {
            name  = "POSTGRES_USER"
            value = var.db_username
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.db_password
          }
          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }
        }
        volume {
          name = "postgres-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.db_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Service for PostgreSQL Database
# Creates an internal ClusterIP service for the backend to connect to the DB.
# -----------------------------------------------------------------------------
resource "kubernetes_service" "db_service" {
  metadata {
    name = "db-service"
    labels = {
      app = "db"
    }
  }
  spec {
    selector = {
      app = "db"
    }
    port {
      protocol    = "TCP"
      port        = 5432
      target_port = 5432
    }
    type = "ClusterIP"
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Deployment for Backend Service (Flask App)
# Deploys multiple replicas of your Flask application.
# -----------------------------------------------------------------------------
resource "kubernetes_deployment" "backend_deployment" {
  metadata {
    name = "backend-deployment"
    labels = {
      app = "backend"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "backend"
      }
    }
    template {
      metadata {
        labels = {
          app = "backend"
        }
      }
      spec {
        container {
          name  = "backend-container"
          image = "${var.ecr_registry_url}/${var.ecr_repo_backend}:${var.image_tag}"
          port {
            container_port = 5000
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "database_url"
              }
            }
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Service for Backend Service
# Creates an internal ClusterIP service for the frontend to connect to the backend.
# -----------------------------------------------------------------------------
resource "kubernetes_service" "backend_service" {
  metadata {
    name = "backend-service"
    labels = {
      app = "backend"
    }
  }
  spec {
    selector = {
      app = "backend"
    }
    port {
      protocol    = "TCP"
      port        = 5000
      target_port = 5000
    }
    type = "ClusterIP"
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Deployment for Frontend Service (Nginx App)
# Deploys multiple replicas of your Nginx frontend application.
# -----------------------------------------------------------------------------
resource "kubernetes_deployment" "frontend_deployment" {
  metadata {
    name = "frontend-deployment"
    labels = {
      app = "frontend"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "frontend"
      }
    }
    template {
      metadata {
        labels = {
          app = "frontend"
        }
      }
      spec {
        container {
          name  = "frontend-container"
          image = "${var.ecr_registry_url}/${var.ecr_repo_frontend}:${var.image_tag}"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Service for Frontend Service
# Creates an AWS Load Balancer to expose the frontend to the internet.
# -----------------------------------------------------------------------------
resource "kubernetes_service" "frontend_service" {
  metadata {
    name = "frontend-service"
    labels = {
      app = "frontend"
    }
  }
  spec {
    selector = {
      app = "frontend"
    }
    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}



######################################
# EKS infra additions (VPC, IAM, EKS)
######################################
data "aws_availability_zones" "available" {}

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "eks-vpc" }
}

resource "aws_subnet" "eks_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "eks-subnet-${count.index}" }
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.eks_cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.eks_cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "eks" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.eks_subnet[*].id
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy]
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.eks_cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.eks_subnet[*].id
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly
  ]
}

# Kubernetes provider wiring (waits for node group)
data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.eks.name
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.eks.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token

  depends_on = [aws_eks_node_group.eks_nodes]
}
