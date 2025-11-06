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
  region = var.aws_region
}

# Security Group
resource "aws_security_group" "ethereum_testnet" {
  name        = "${var.project_name}-sg"
  description = "Security group for Ethereum testnet"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # Ethereum RPC
  ingress {
    from_port   = 8545
    to_port     = 8545
    protocol    = "tcp"
    cidr_blocks = var.allowed_rpc_cidrs
    description = "Ethereum RPC"
  }

  # Ethereum WS
  ingress {
    from_port   = 8546
    to_port     = 8546
    protocol    = "tcp"
    cidr_blocks = var.allowed_rpc_cidrs
    description = "Ethereum WebSocket"
  }

  # Beacon API
  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = var.allowed_rpc_cidrs
    description = "Beacon Chain API"
  }

  # P2P ports
  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Ethereum P2P TCP"
  }

  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Ethereum P2P UDP"
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Beacon P2P TCP"
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Beacon P2P UDP"
  }

  # Kurtosis dynamic port range
  ingress {
    from_port   = 32768
    to_port     = 33768
    protocol    = "tcp"
    cidr_blocks = var.allowed_rpc_cidrs
    description = "Kurtosis dynamic ports"
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# EC2 Instance - Chain Node (High Tier)
resource "aws_instance" "ethereum_chain" {
  ami           = var.ami_id
  instance_type = var.chain_instance_type
  key_name      = var.key_pair_name
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.ethereum_testnet.id]

  root_block_device {
    volume_size           = var.chain_volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    project_name = var.project_name
  })

  tags = {
    Name    = "${var.project_name}-chain"
    Project = var.project_name
    Role    = "chain"
  }
}

# EC2 Instance - TPS Test Node
resource "aws_instance" "ethereum_tps" {
  ami           = var.ami_id
  instance_type = var.tps_instance_type
  key_name      = var.key_pair_name
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.ethereum_testnet.id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    project_name = "${var.project_name}-tps"
  })

  tags = {
    Name    = "${var.project_name}-tps"
    Project = var.project_name
    Role    = "tps-test"
  }
}

# Elastic IP - Chain Node
resource "aws_eip" "ethereum_chain" {
  count    = var.use_elastic_ip ? 1 : 0
  instance = aws_instance.ethereum_chain.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-chain-eip"
    Project = var.project_name
  }
}

# Elastic IP - TPS Node
resource "aws_eip" "ethereum_tps" {
  count    = var.use_elastic_ip ? 1 : 0
  instance = aws_instance.ethereum_tps.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-tps-eip"
    Project = var.project_name
  }
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    chain_ip  = var.use_elastic_ip ? aws_eip.ethereum_chain[0].public_ip : aws_instance.ethereum_chain.public_ip
    tps_ip    = var.use_elastic_ip ? aws_eip.ethereum_tps[0].public_ip : aws_instance.ethereum_tps.public_ip
    user      = var.ssh_user
    key_file  = var.ssh_private_key_path
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
