terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.11.0"
    }
  }
}


provider "aws" {
  region = var.aws_region
}

# -------------------------
# Networking: VPC & Public Subnets
# -------------------------
data "aws_availability_zones" "available" {}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.eks_cluster_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.eks_cluster_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.eks_cluster_name}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.eks_cluster_name}-public-rt" }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -------------------------



# -------------------------
# IAM Roles for EKS + Node Group
# -------------------------
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.eks_cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_attach" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.eks_cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_attach_worker" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_attach_cni" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_attach_ecr" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -------------------------
# EKS Cluster
# -------------------------
resource "aws_eks_cluster" "eks" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.public[*].id
    endpoint_public_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_attach]
}

# -------------------------
# Managed Node Group
# -------------------------
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.eks_cluster_name}-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public[*].id
  instance_types  = [var.instance_type]

  scaling_config {
    desired_size = var.desired_capacity
    max_size     = max(1, var.desired_capacity + 1)
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_attach_worker,
    aws_iam_role_policy_attachment.node_attach_cni,
    aws_iam_role_policy_attachment.node_attach_ecr
  ]
}

# -------------------------
# RDS Postgres (for demo)
# -------------------------
resource "aws_db_subnet_group" "db_subnet" {
  name       = "${var.eks_cluster_name}-db-subnet"
  subnet_ids = aws_subnet.public[*].id
  tags       = { Name = "${var.eks_cluster_name}-db-subnet" }
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.eks_cluster_name}-postgres"
  allocated_storage      = var.db_allocated_storage
  engine                 = "postgres"
  engine_version         = "13.21"  # ✅ Updated to a supported version
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  publicly_accessible    = true
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  tags = {
    Name = "${var.eks_cluster_name}-postgres"
  }

  depends_on = [aws_db_subnet_group.db_subnet]
}


resource "aws_security_group" "rds_sg" {
  name   = "${var.eks_cluster_name}-rds-sg"
  vpc_id = aws_vpc.this.id
  description = "Allow database access from VPC CIDR (demo)"
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.public_access_cidrs_for_rds
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.eks_cluster_name}-rds-sg" }
}

# -------------------------
# Kubernetes provider (after cluster + nodes)
# -------------------------
data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.eks.name
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.eks.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
  depends_on = [aws_eks_node_group.node_group] # ✅ Allowed here
}


# -------------------------
# Kubernetes resources: secret, backend/frontend deployments, services
# -------------------------
resource "kubernetes_secret" "db_credentials" {
  metadata {
    name = "db-credentials"
  }

  data = {
    database_url = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:5432/${var.db_name}"
  }

  type = "Opaque"
}


# Backend deployment
resource "kubernetes_deployment" "backend" {
  metadata {
    name = "backend-deployment"
    labels = { app = "backend" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "backend" } }
    template {
      metadata { labels = { app = "backend" } }
      spec {
        container {
          name  = "backend-container"
          image = "public.ecr.aws/n7o2b0o4/backend"
          port { container_port = 5000 }
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
resource "kubernetes_service" "backend" {
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
      port        = 80        # Service port
      target_port = 5000      # Container port
    }

    type = "LoadBalancer"
  }
}



# Frontend deployment
resource "kubernetes_deployment" "frontend" {
  metadata {
    name = "frontend-deployment"
    labels = { app = "frontend" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "frontend" } }
    template {
      metadata { labels = { app = "frontend" } }
      spec {
        container {
          name  = "frontend-container"
          image = "public.ecr.aws/n7o2b0o4/frontend:latest"
          port { container_port = 80 }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
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
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
  }


resource "kubernetes_ingress_v1" "app_ingress" {
  metadata {
    name      = "app-ingress"
    namespace = "default"
    annotations = {
      kubernetes.io/ingress.class = "nginx"
      nginx.ingress.kubernetes.io/rewrite-target = "/$1"
    }
  }

  spec {
    rule {
      http {
        path {
          path     = "/api/(.*)"
          path_type = "Prefix"
          backend {
            service {
              name = "backend-service"
              port {
                number = 5000
              }
            }
          }
        }

        path {
          path     = "/(.*)"
          path_type = "Prefix"
          backend {
            service {
              name = "frontend-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

