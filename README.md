# Clusterra Connect

Connect your AWS ParallelCluster to Clusterra for unified HPC management.

## Prerequisites

- **Python 3.10+**
- **AWS CLI** configured (`aws configure`)
- **[OpenTofu](https://opentofu.org/)** (`tofu`) or Terraform
- **AWS ParallelCluster** (`pcluster`) installed via pip

## Quick Start (Recommended)

The easiest way to connect is using our interactive installer, which handles infrastructure deployment and API registration automatically.

```bash
# 1. Clone the repository
git clone https://github.com/clusterra/clusterra-connect.git
cd clusterra-connect

# 2. Install dependencies
pip install -r requirements.txt

# 3. Run the installer
python3 install.py
```

### What the Installer Does

1.  **Configuration**: Interactive prompts to select your Region, VPC, and Subnets (supports both new cluster creation and existing clusters).
2.  **Infrastructure**: Uses OpenTofu to deploy a **VPC Lattice** service association, enabling secure communication between your cluster and Clusterra.
3.  **Registration**: Automatically registers your cluster with the Clusterra API using your Tenant ID.

### Connecting an Existing Cluster

If you already have a running ParallelCluster:
1.  Select **"Existing Cluster"** in the installer.
2.  Provide the **Head Node Instance ID** (e.g., `i-0123456789abcdef0`).
3.  The installer will inspect the instance to identify the correct VPC and Subnet, then deploy the necessary connectivity layer.

## Architecture

Clusterra Connect uses **AWS VPC Lattice** for secure, private connectivity without exposing your cluster to the public internet.

- **Private**: No public IPs required for API communication.
- **Secure**: Cross-account access is strictly controlled via IAM and Lattice Service Network policies.
- **Automated**: The installer handles the Lattice Service association and RAM resource share acceptance.

## Troubleshooting

### "Authentication Failed"
Ensure your AWS CLI is configured for the correct account and region:
```bash
aws sts get-caller-identity
```

### "ToFu/Terraform Error"
If the installer fails during the infrastructure phase, you can inspect the logs or try running Tofu manually for more details:
```bash
tofu init
tofu apply -var-file=generated/terraform.tfvars
```

### "RAM Invitation Pending"
The installer waits for the RAM Resource Share invitation from Clusterra. If it times out, you can check for pending invitations in the [AWS RAM Console](https://console.aws.amazon.com/ram/home#ResourceShareInvitations:).

## Clean Up

To remove all resources and disconnect the cluster:

```bash
# Destroy cloud resources
tofu destroy -var-file=generated/terraform.tfvars

# If you created a new cluster via the installer, also delete it:
pcluster delete-cluster --cluster-name <your-cluster-name> --region <region>
```
