# Clusterra ParallelCluster Module
#
# Creates an AWS ParallelCluster with Slurm scheduler.
# Uses the AWS ParallelCluster CLI via a null_resource provisioner.
#
# Deployed in: CUSTOMER's AWS account

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ─── Variables ─────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the ParallelCluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the cluster"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for head node"
  type        = string
}

variable "ssh_key_name" {
  description = "EC2 SSH key pair name"
  type        = string
}

variable "head_node_instance_type" {
  description = "Instance type for head node"
  type        = string
  default     = "t3.small"
}

variable "compute_instance_type" {
  description = "Instance type for compute nodes"
  type        = string
  default     = "c5.large"
}

variable "min_count" {
  description = "Minimum compute nodes"
  type        = number
  default     = 0
}

variable "max_count" {
  description = "Maximum compute nodes"
  type        = number
  default     = 10
}

# (Storage variables removed)

# ─── Data Sources ──────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# (Slurm JWT Secret removed - handled by connect module)

# ─── EFS (for demo/dev) ────────────────────────────────────────────────────

# ─── EFS (for demo/dev) ────────────────────────────────────────────────────

# (EFS resources removed - managed by pcluster natively)

locals {
  # EFS-only shared storage config (simplifies type issues)
  # Managed EFS configuration (pcluster creates/manages it)
  efs_storage = [
    {
      Name        = "shared"
      StorageType = "Efs"
      MountDir    = "/shared"
    }
  ]

  cluster_config = yamlencode({
    Region = var.region

    Image = {
      Os = "alinux2023"
    }

    HeadNode = {
      InstanceType = var.head_node_instance_type
      Networking = {
        SubnetId = var.subnet_id
      }
      Ssh = {
        KeyName = var.ssh_key_name
      }
      Iam = {
        AdditionalIamPolicies = [
          { Policy = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" },
          { Policy = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" },
          { Policy = "arn:aws:iam::aws:policy/AmazonSQSFullAccess" }
        ]
      }
      LocalStorage = {
        RootVolume = {
          Size = 50
        }
      }
    }

    Scheduling = {
      Scheduler = "slurm"
      SlurmSettings = {
        ScaledownIdletime = 5
      }
      SlurmQueues = [
        {
          Name = "compute"
          ComputeResources = [
            {
              Name         = "spot"
              InstanceType = var.compute_instance_type
              MinCount     = var.min_count
              MaxCount     = var.max_count
            }
          ]
          ComputeSettings = {
            LocalStorage = {
              RootVolume = {
                Size = 50
              }
            }
          }
          CapacityType = "SPOT"
          Networking = {
            SubnetIds = [var.subnet_id]
          }
        }
      ]
    }

    SharedStorage = local.efs_storage
  })
}

# Write cluster config to file
resource "local_file" "cluster_config" {
  content  = local.cluster_config
  filename = "${path.root}/generated/${var.cluster_name}-config.yaml"
}

# ─── Outputs ───────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "ParallelCluster name"
  value       = var.cluster_name
}

output "cluster_config_path" {
  description = "Path to generated cluster config file"
  value       = local_file.cluster_config.filename
}

# (JWT outputs removed)

# (shared_storage_id output removed)

output "deploy_command" {
  description = "Command to create the cluster (run after tofu apply)"
  value       = "pcluster create-cluster --cluster-name ${var.cluster_name} --cluster-configuration ${local_file.cluster_config.filename} --region ${var.region}"
}

output "head_node_ip_command" {
  description = "Command to get head node private IP (after cluster is created)"
  value       = "pcluster describe-cluster --cluster-name ${var.cluster_name} --region ${var.region} | jq -r '.headNode.privateIpAddress'"
}
