# Clusterra Connect - Customer Onboarding
#
# This single file creates everything needed to connect your existing
# ParallelCluster to Clusterra's control plane.
#
# Prerequisites:
#   - An existing AWS ParallelCluster
#   - slurmrestd enabled and listening on port 6820
#   - OpenTOFU or Terraform installed
#
# Usage:
#   1. Copy this file to your infrastructure directory
#   2. Edit terraform.tfvars (see example below)
#   3. Run: tofu init && tofu apply
#   4. Copy the outputs to Clusterra console
#
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
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

provider "aws" {
  region = var.region
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES - Set these in terraform.tfvars
# ─────────────────────────────────────────────────────────────────────────────

variable "region" {
  description = "AWS region where your ParallelCluster runs"
  type        = string
}

variable "cluster_name" {
  description = "Name of your ParallelCluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ParallelCluster runs"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the head node runs"
  type        = string
}

variable "slurm_jwt_secret_name" {
  description = "Name of the Secrets Manager secret containing your Slurm JWT key"
  type        = string
  default     = "slurm-jwt-key"
}

variable "slurm_api_port" {
  description = "Port where slurmrestd listens"
  type        = number
  default     = 6820
}

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

locals {
  clusterra_account_id = "306847926740"
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Find the head node by ParallelCluster tags
data "aws_instances" "head_node" {
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

# Generate a unique customer ID
resource "random_id" "customer" {
  byte_length = 4
}

locals {
  customer_id = "cust-${random_id.customer.hex}"
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM ROLE - Allows Clusterra to fetch your Slurm JWT secret
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "clusterra_access" {
  name = "clusterra-access-${local.customer_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${local.clusterra_account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "clusterra-${local.customer_id}"
        }
      }
    }]
  })

  tags = {
    Purpose   = "Clusterra cross-account access"
    ManagedBy = "OpenTOFU"
  }
}

resource "aws_iam_role_policy" "secrets_access" {
  name = "clusterra-secrets-access"
  role = aws_iam_role.clusterra_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.slurm_jwt_secret_name}*"]
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# NLB - Routes traffic to your head node's Slurm API
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "slurm_api" {
  name               = "clusterra-${local.customer_id}"
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.subnet_id]

  tags = {
    Name      = "clusterra-nlb-${local.customer_id}"
    ManagedBy = "OpenTOFU"
  }
}

resource "aws_lb_target_group" "slurm_api" {
  name        = "clusterra-${local.customer_id}"
  port        = var.slurm_api_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = var.slurm_api_port
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
}

resource "aws_lb_target_group_attachment" "head_node" {
  target_group_arn = aws_lb_target_group.slurm_api.arn
  target_id        = data.aws_instances.head_node.ids[0]
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
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC ENDPOINT SERVICE - Exposes NLB to Clusterra via PrivateLink
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_vpc_endpoint_service" "slurm_api" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.slurm_api.arn]

  allowed_principals = [
    "arn:aws:iam::${local.clusterra_account_id}:root"
  ]

  tags = {
    Name      = "clusterra-${local.customer_id}"
    ManagedBy = "OpenTOFU"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS - Copy these to Clusterra console
# ─────────────────────────────────────────────────────────────────────────────

output "clusterra_onboarding" {
  description = "Copy ALL of these values to Clusterra console"
  value = {
    aws_account_id        = data.aws_caller_identity.current.account_id
    role_arn              = aws_iam_role.clusterra_access.arn
    external_id           = "clusterra-${local.customer_id}"
    vpc_endpoint_service  = aws_vpc_endpoint_service.slurm_api.service_name
    slurm_jwt_secret_arn  = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.slurm_jwt_secret_name}"
  }
}
