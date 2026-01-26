# Clusterra Connect

Connect your AWS ParallelCluster to Clusterra for unified HPC management.

## Prerequisites

- AWS credentials configured
- [OpenTOFU](https://opentofu.org/) or Terraform installed
- Python 3.10+ (for interactive installer)

## Quick Start

### Option 1: Interactive Installer (Recommended)

```bash
git clone https://github.com/clusterra/clusterra-connect.git
cd clusterra-connect

pip install -r requirements.txt
python install.py
```

The installer will:
- Auto-detect your AWS region, VPCs, and subnets
- Guide you through scenario selection (new cluster vs existing)
- Generate `terraform.tfvars` with your configuration
- Run OpenTofu to deploy infrastructure
- Register your cluster with Clusterra API

### Option 2: Manual Configuration

```bash
git clone https://github.com/clusterra/clusterra-connect.git
cd clusterra-connect

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your cluster details

# Deploy
tofu init
tofu apply

# Copy outputs to Clusterra console
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
