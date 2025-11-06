variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "ethereum-testnet"
}

variable "chain_instance_type" {
  description = "EC2 instance type for chain node"
  type        = string
  default     = "c6i.4xlarge"  # 16 vCPU, 32 GB RAM
}

variable "tps_instance_type" {
  description = "EC2 instance type for TPS test node"
  type        = string
  default     = "t3.medium"  # 2 vCPU, 4 GB RAM
}

variable "ami_id" {
  description = "AMI ID (Ubuntu 22.04 recommended)"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "AWS key pair name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "chain_volume_size" {
  description = "Root volume size in GB for chain node"
  type        = number
  default     = 200
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_rpc_cidrs" {
  description = "CIDR blocks allowed to access RPC"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "use_elastic_ip" {
  description = "Whether to use Elastic IP"
  type        = bool
  default     = true
}

variable "ssh_user" {
  description = "SSH user for Ansible"
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/id_rsa"
}
