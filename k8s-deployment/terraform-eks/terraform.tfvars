# Terraform variables for EKS deployment

aws_region         = "ap-southeast-1"
cluster_name       = "ethereum-testnet"
kubernetes_version = "1.31"

vpc_cidr             = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

tags = {
  Environment = "testnet"
  Project     = "ethereum-testnet"
  ManagedBy   = "terraform"
  Owner       = "chengfeng.fan@merquri.io"
}
