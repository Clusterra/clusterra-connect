# Clusterra Events Module Variables

variable "cluster_name" {
  description = "Name of the ParallelCluster"
  type        = string
}

variable "cluster_id" {
  description = "Clusterra cluster ID (clus_xxx)"
  type        = string
}

variable "tenant_id" {
  description = "Clusterra tenant ID (ten_xxx)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "clusterra_api_url" {
  description = "Clusterra API URL"
  type        = string
  default     = "https://api.clusterra.cloud"
}

variable "head_node_instance_id" {
  description = "Head node EC2 instance ID (for filtering CloudWatch events)"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (SQS, Lambda env vars). If not provided, uses AWS managed keys."
  type        = string
  default     = null
}

variable "vpc_config" {
  description = "VPC configuration for Lambda function"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for Lambda function"
  type        = number
  default     = 10
}

variable "code_signing_config_arn" {
  description = "Code signing configuration ARN for Lambda"
  type        = string
  default     = null
}
