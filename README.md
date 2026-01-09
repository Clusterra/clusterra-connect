# Clusterra Connect

Connect your existing AWS ParallelCluster to Clusterra in 3 simple steps.

## Prerequisites

- An existing AWS ParallelCluster with slurmrestd enabled (port 6820)
- A Slurm JWT key stored in AWS Secrets Manager
- [OpenTOFU](https://opentofu.org/) or Terraform installed

## Quick Start

```bash
# 1. Clone or copy this directory
git clone https://github.com/clusterra/clusterra-connect.git
cd clusterra-connect

# 2. Configure your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your cluster details

# 3. Deploy
tofu init
tofu apply

# 4. Copy outputs to Clusterra console
tofu output -json clusterra_onboarding
```

## What This Creates

| Resource | Purpose |
|----------|---------|
| **IAM Role** | Allows Clusterra to fetch your Slurm JWT secret |
| **NLB** | Routes traffic to your head node's Slurm API |
| **VPC Endpoint Service** | Exposes NLB via PrivateLink (no public access) |

## Security

- ✅ No public exposure - uses AWS PrivateLink
- ✅ Cross-account access requires ExternalId verification
- ✅ Clusterra only has read access to your JWT secret
- ✅ All traffic stays on AWS backbone network

## Outputs

After `tofu apply`, you'll get these values to enter in Clusterra console:

```
aws_account_id       = "123456789012"
role_arn             = "arn:aws:iam::123456789012:role/clusterra-access-cust-abc123"
external_id          = "clusterra-cust-abc123"
vpc_endpoint_service = "com.amazonaws.vpce.ap-south-1.vpce-svc-xxx"
slurm_jwt_secret_arn = "arn:aws:secretsmanager:ap-south-1:123456789012:secret:slurm-jwt-key"
```

## Cleanup

To disconnect from Clusterra:

```bash
tofu destroy
```
