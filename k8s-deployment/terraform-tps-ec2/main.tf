terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "kt-eth-testnet"
}

variable "instance_type" {
  description = "EC2 instance type for TPS testing"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

# Get VPC from EKS cluster
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_vpc" "cluster_vpc" {
  id = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
}

data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.cluster_vpc.id]
  }
  
  tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

# Get EKS cluster security group
data "aws_security_group" "cluster_sg" {
  vpc_id = data.aws_vpc.cluster_vpc.id
  
  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [var.cluster_name]
  }
}

# Security group for TPS test instance
resource "aws_security_group" "tps_test" {
  name_prefix = "tps-test-"
  description = "Security group for TPS test EC2 instance"
  vpc_id      = data.aws_vpc.cluster_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tps-test-sg"
  }
}

# Get EKS node security group
data "aws_security_group" "node_sg" {
  vpc_id = data.aws_vpc.cluster_vpc.id
  
  filter {
    name   = "group-name"
    values = ["${var.cluster_name}-node-*"]
  }
}

# Allow EC2 instance to access EKS cluster API
resource "aws_security_group_rule" "eks_from_tps_test" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.tps_test.id
  security_group_id        = data.aws_security_group.cluster_sg.id
  description              = "Allow TPS test instance to access EKS API"
}

# Allow EC2 instance to access RPC NodePorts on EKS nodes
resource "aws_security_group_rule" "node_rpc_from_tps_test" {
  type                     = "ingress"
  from_port                = 30545
  to_port                  = 30552
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.tps_test.id
  security_group_id        = data.aws_security_group.node_sg.id
  description              = "Allow TPS test instance to access RPC NodePorts"
}

# IAM role for EC2 instance
resource "aws_iam_role" "tps_test" {
  name_prefix = "tps-test-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# IAM policy for EKS and EC2 access
resource "aws_iam_role_policy" "tps_test_eks" {
  name_prefix = "tps-test-eks-"
  role        = aws_iam_role.tps_test.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "tps_test" {
  name_prefix = "tps-test-"
  role        = aws_iam_role.tps_test.name
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 instance for TPS testing
resource "aws_instance" "tps_test" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = tolist(data.aws_subnets.public_subnets.ids)[0]
  vpc_security_group_ids      = [aws_security_group.tps_test.id]
  iam_instance_profile        = aws_iam_instance_profile.tps_test.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              EOF

  tags = {
    Name = "tps-test-instance"
  }
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.tps_test.id
}

output "instance_public_ip" {
  description = "Public IP of TPS test instance"
  value       = aws_instance.tps_test.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.tps_test.public_ip}"
}
