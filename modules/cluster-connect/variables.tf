variable "region" {
  description = "AWS Region"
  type        = string
}

variable "cluster_name" {
  description = "Cluster Name (matches ParallelCluster name)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the head node runs"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID (same as head node)"
  type        = string
}

variable "slurm_api_port" {
  description = "Port where slurmrestd listens"
  type        = number
  default     = 6830
}

variable "head_node_instance_id" {
  description = "Instance ID of head node (optional - auto-discovered via pcluster tags if not provided)"
  type        = string
  default     = ""
}

variable "clusterra_account_id" {
  description = "Clusterra's AWS account ID for cross-account access"
  type        = string
  default     = "306847926740"
}

variable "clusterra_service_network_id" {
  description = "Clusterra's VPC Lattice Service Network ID (from Control Plane)"
  type        = string
}

variable "cluster_id" {
  description = "Clusterra cluster ID (8 chars: clusa1b2)"
  type        = string
}
