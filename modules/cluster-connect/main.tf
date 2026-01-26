# Clusterra Connect Module
#
# Creates the PrivateLink connectivity layer for Clusterra to access the cluster's Slurm API:
# 1. Network Load Balancer → Head Node port 6830 (slurmrestd)
# 2. VPC Endpoint Service → Exposes NLB to Clusterra via PrivateLink
# 3. IAM Role → Allows Clusterra to assume role and read JWT secret
#
# Deployed in: CUSTOMER's AWS account

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS & LOCALS
# ─────────────────────────────────────────────────────────────────────────────

locals {
  cluster_short_id = "cust-${substr(sha256(var.cluster_name), 0, 8)}"  # Short ID for AWS resources with name limits
  clusterra_account_id = "306847926740"  # Clusterra's AWS account
}

# Generate a unique customer ID for resource naming
resource "random_id" "customer" {
  byte_length = 4
}

locals {
  customer_id = "cust-${random_id.customer.hex}"
  
  # Use provided instance_id or look it up via tags
  target_instance_id = var.head_node_instance_id != "" ? var.head_node_instance_id : (
    length(data.aws_instances.head_node) > 0 && length(data.aws_instances.head_node[0].ids) > 0 
    ? data.aws_instances.head_node[0].ids[0] 
    : null
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Create JWT Secret for Clusterra integration
resource "random_password" "slurm_jwt_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "slurm_jwt" {
  name                    = "clusterra-slurm-jwt-${var.cluster_name}"
  description             = "Slurm JWT HS256 key for Clusterra authentication"
  recovery_window_in_days = 30  # Production-safe: 30-day recovery window

  tags = {
    Purpose   = "Clusterra Slurm authentication"
    ManagedBy = "OpenTOFU"
  }
}

resource "aws_secretsmanager_secret_version" "slurm_jwt" {
  secret_id     = aws_secretsmanager_secret.slurm_jwt.id
  secret_string = random_password.slurm_jwt_key.result
}

# Find the head node by ParallelCluster tags (ONLY if head_node_instance_id is not provided)
data "aws_instances" "head_node" {
  count = var.head_node_instance_id == "" ? 1 : 0

  filter {
    name   = "tag:parallelcluster:cluster-name"
    values = [var.cluster_name]
  }
  filter {
    name   = "tag:parallelcluster:node-type"
    values = ["HeadNode"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUP
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "nlb_target" {
  # checkov:skip=CKV2_AWS_5:Security group is attached to NLB target group
  name        = "clusterra-nlb-sg-${var.cluster_name}"
  description = "Allow slurmrestd traffic from NLB to head node"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.slurm_api_port
    to_port     = var.slurm_api_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    description = "Allow slurmrestd traffic from VPC (via NLB)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    description = "Allow all outbound to VPC"
  }

  tags = {
    Name      = "clusterra-nlb-sg-${var.cluster_name}"
    ManagedBy = "OpenTOFU"
    Cluster   = var.cluster_name
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# NETWORK LOAD BALANCER
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "slurm_api" {
  name               = "clusterra-nlb-${local.cluster_short_id}"  # Short ID for 32-char limit
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.subnet_id]

  enable_deletion_protection = false

  tags = {
    Name      = "clusterra-nlb-${local.customer_id}"
    ManagedBy = "OpenTOFU"
    Cluster   = var.cluster_name
  }
}

resource "aws_lb_target_group" "slurm_api" {
  name        = "clusterra-tg-${local.cluster_short_id}"  # Short ID for 32-char limit
  port        = var.slurm_api_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.slurm_api_port
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = {
    Name      = "clusterra-tg-${var.cluster_name}"  # Use full name in tags for readability
    ManagedBy = "OpenTOFU"
  }
}

# Register head node as target (using instance ID)
resource "aws_lb_target_group_attachment" "head_node" {
  count = local.target_instance_id != null ? 1 : 0

  target_group_arn = aws_lb_target_group.slurm_api.arn
  target_id        = local.target_instance_id
  port             = var.slurm_api_port
}

resource "aws_lb_listener" "slurm_api" {
  load_balancer_arn = aws_lb.slurm_api.arn
  port              = var.slurm_api_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.slurm_api.arn
  }

  tags = {
    Name      = "clusterra-listener-${local.customer_id}"
    ManagedBy = "OpenTOFU"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC ENDPOINT SERVICE (PrivateLink)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_vpc_endpoint_service" "slurm_api" {
  acceptance_required        = false  # Auto-accept from Clusterra
  network_load_balancer_arns = [aws_lb.slurm_api.arn]

  # Allow Clusterra's AWS account to create endpoints
  allowed_principals = ["arn:aws:iam::${local.clusterra_account_id}:root"]

  tags = {
    Name      = "clusterra-${local.customer_id}"
    ManagedBy = "OpenTOFU"
    Cluster   = var.cluster_name
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM ROLE FOR CLUSTERRA CROSS-ACCOUNT ACCESS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "clusterra_access" {
  name = "clusterra-access-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.clusterra_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "clusterra-${var.cluster_name}"
          }
        }
      }
    ]
  })

  tags = {
    Name      = "clusterra-access-${var.cluster_name}"
    ManagedBy = "OpenTOFU"
    Cluster   = var.cluster_name
  }
}

resource "aws_iam_role_policy" "secrets_access" {
  name = "clusterra-secrets-access"
  role = aws_iam_role.clusterra_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadJWTSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.slurm_jwt.arn
      }
    ]
  })
}

# EC2 permissions for start/stop cluster
resource "aws_iam_role_policy" "ec2_access" {
  name = "clusterra-ec2-access"
  role = aws_iam_role.clusterra_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeAllInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageClusterInstances"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/parallelcluster:cluster-name" = var.cluster_name
          }
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS - Values for Clusterra API registration
# ─────────────────────────────────────────────────────────────────────────────

output "clusterra_onboarding" {
  description = "Copy ALL of these values to Clusterra console or use for API registration"
  value = {
    cluster_name          = var.cluster_name
    region                = data.aws_region.current.name
    aws_account_id        = data.aws_caller_identity.current.account_id
    vpc_endpoint_service  = aws_vpc_endpoint_service.slurm_api.service_name
    slurm_port            = var.slurm_api_port
    slurm_jwt_secret_arn  = aws_secretsmanager_secret.slurm_jwt.arn
    role_arn              = aws_iam_role.clusterra_access.arn
    external_id           = "clusterra-${var.cluster_name}"
    head_node_instance_id = local.target_instance_id
    nlb_dns               = aws_lb.slurm_api.dns_name
  }
}

output "nlb_arn" {
  description = "NLB ARN"
  value       = aws_lb.slurm_api.arn
}

output "vpc_endpoint_service_name" {
  description = "VPC Endpoint Service name for Clusterra to connect"
  value       = aws_vpc_endpoint_service.slurm_api.service_name
}

output "iam_role_arn" {
  description = "IAM Role ARN for Clusterra cross-account access"
  value       = aws_iam_role.clusterra_access.arn
}

output "external_id" {
  description = "External ID for STS AssumeRole"
  value       = "clusterra-${var.cluster_name}"
  sensitive   = true
}

output "customer_id" {
  description = "Unique customer ID for this deployment"
  value       = local.customer_id
}
