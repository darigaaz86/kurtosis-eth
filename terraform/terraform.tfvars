# AWS Configuration
aws_region = "ap-southeast-1"

# Required: AWS Key Pair (must exist in your AWS account)
key_pair_name = "sonicKey"

# Required: Network Configuration
vpc_id    = "vpc-0d81c8d64b7628d1a"
subnet_id = "subnet-0ac3849de84a697e4"

# Required: AMI ID (Ubuntu 22.04 LTS recommended)
# Find AMI: https://cloud-images.ubuntu.com/locator/ec2/
# Example for us-east-1: ami-0c7217cdde317cfec
ami_id = "ami-0827b3068f1548bf6"

# SSH Configuration
ssh_private_key_path = "~/.ssh/sonicKey.pem"
ssh_user             = "ubuntu"

# Instance Configuration
chain_instance_type = "c6i.8xlarge"  # 32 vCPU, 64 GB RAM
tps_instance_type   = "t3.medium"    # 2 vCPU, 4 GB RAM
chain_volume_size   = 200            # GB

# Project Settings
project_name = "ethereum-testnet"

# Security (restrict these in production!)
allowed_ssh_cidrs = ["0.0.0.0/0"]
allowed_rpc_cidrs = ["0.0.0.0/0"]

# Elastic IP (disabled for TPS node to avoid limit)
use_elastic_ip = true
