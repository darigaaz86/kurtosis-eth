# TPS Test EC2 Instance - Terraform

This Terraform configuration creates an EC2 instance in the same VPC as your EKS cluster for running TPS tests with low latency.

## Prerequisites

- AWS CLI configured
- Terraform installed
- EKS cluster already deployed
- SSH key pair in AWS

## Quick Start

```bash
# Update terraform.tfvars with your settings
vim terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply

# Get connection info
terraform output ssh_command
```

## Configuration

Edit `terraform.tfvars`:

```hcl
region        = "ap-southeast-1"
cluster_name  = "ethereum-testnet"
instance_type = "t3.large"
key_name      = "your-ssh-key"
```

## What Gets Created

- EC2 instance (t3.large by default)
- Security group (SSH access)
- IAM role with EKS access permissions
- Instance profile

## Outputs

- `instance_id` - EC2 instance ID
- `instance_public_ip` - Public IP address
- `ssh_command` - Ready-to-use SSH command

## Cleanup

```bash
terraform destroy
```
