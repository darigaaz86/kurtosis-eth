output "chain_instance_id" {
  description = "Chain node EC2 instance ID"
  value       = aws_instance.ethereum_chain.id
}

output "tps_instance_id" {
  description = "TPS test node EC2 instance ID"
  value       = aws_instance.ethereum_tps.id
}

output "chain_public_ip" {
  description = "Chain node public IP address"
  value       = var.use_elastic_ip ? aws_eip.ethereum_chain[0].public_ip : aws_instance.ethereum_chain.public_ip
}

output "tps_public_ip" {
  description = "TPS test node public IP address"
  value       = var.use_elastic_ip ? aws_eip.ethereum_tps[0].public_ip : aws_instance.ethereum_tps.public_ip
}

output "chain_private_ip" {
  description = "Chain node private IP address"
  value       = aws_instance.ethereum_chain.private_ip
}

output "tps_private_ip" {
  description = "TPS test node private IP address"
  value       = aws_instance.ethereum_tps.private_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.ethereum_testnet.id
}

output "rpc_endpoint" {
  description = "Ethereum RPC endpoint (internal)"
  value       = "http://${var.use_elastic_ip ? aws_eip.ethereum_chain[0].public_ip : aws_instance.ethereum_chain.public_ip}:8545"
}

output "ws_endpoint" {
  description = "Ethereum WebSocket endpoint (internal)"
  value       = "ws://${var.use_elastic_ip ? aws_eip.ethereum_chain[0].public_ip : aws_instance.ethereum_chain.public_ip}:8546"
}

output "beacon_api_endpoint" {
  description = "Beacon Chain API endpoint (internal)"
  value       = "http://${var.use_elastic_ip ? aws_eip.ethereum_chain[0].public_ip : aws_instance.ethereum_chain.public_ip}:4000"
}

output "ssh_chain" {
  description = "SSH command to connect to chain node"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${var.use_elastic_ip ? aws_eip.ethereum_chain[0].public_ip : aws_instance.ethereum_chain.public_ip}"
}

output "ssh_tps" {
  description = "SSH command to connect to TPS node"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${var.use_elastic_ip ? aws_eip.ethereum_tps[0].public_ip : aws_instance.ethereum_tps.public_ip}"
}
