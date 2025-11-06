# Ethereum Testnet Deployment

Automated deployment of a private Ethereum testnet with 8 Reth nodes, Lighthouse consensus clients, and comprehensive monitoring stack.

## Features

- **8-Node Ethereum Network**: Reth execution layer + Lighthouse consensus layer
- **Automated Deployment**: Terraform + Ansible for infrastructure and configuration
- **Performance Monitoring**: Grafana dashboards with txpool metrics
- **TPS Testing**: Go-based tool for high-throughput transaction testing
- **Production Ready**: Optimized for performance testing and development

## Architecture

- **Chain Node**: c6i.4xlarge EC2 instance running 8 Reth + Lighthouse nodes via Kurtosis
- **TPS Node**: t3.medium EC2 instance for transaction load generation
- **Monitoring**: Prometheus + Grafana + custom txpool exporter
- **Network**: Private testnet with 3-second block time, 600M gas limit

## Prerequisites

- AWS account with configured credentials
- Terraform >= 1.0
- Ansible >= 2.9
- SSH key pair in AWS (default: `sonicKey`)

## Quick Start

### 1. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS settings
```

### 2. Deploy

```bash
./deploy.sh
```

The script will:
1. Provision EC2 instances with Terraform
2. Deploy Ethereum testnet with Ansible
3. Configure monitoring and dashboards
4. Display access information

### 3. Access Services

After deployment completes, you'll receive:

- **RPC Endpoints**: 8 nodes on dynamic ports (32xxx-33xxx)
- **Grafana**: http://CHAIN_IP:PORT (admin/admin)
- **Prometheus**: http://CHAIN_IP:PORT
- **Txpool Metrics**: http://CHAIN_IP:9200/metrics

## Configuration

### Network Parameters

Edit `network_params.yaml` to customize:

```yaml
network_params:
  network_id: "3151908"
  seconds_per_slot: 3
  genesis_gaslimit: 600000000
```

### Txpool Settings

Reth nodes are configured with:
- Pending transactions: 50,000 max
- Queued transactions: 50,000 max

## TPS Testing

### Build TPS Tool

```bash
cd ansible
go build -o tps-test-v2 tps-test-v2.go
```

### Run Test

```bash
./tps-test-v2 \
  -tps 1000 \
  -duration 300 \
  -endpoints "http://IP:PORT1,http://IP:PORT2,..." \
  -addresses addresses.json \
  -funders "GENESIS_KEY1,GENESIS_KEY2,..." \
  -chain-id 3151908 \
  -gas-price 1000000000 \
  -gas-limit 21000
```

### Parameters

- `-tps`: Target transactions per second
- `-duration`: Test duration in seconds (0 = infinite)
- `-endpoints`: Comma-separated RPC URLs
- `-addresses`: JSON file with test accounts
- `-funders`: Genesis account private keys for funding
- `-skip-funding`: Skip account funding phase
- `-chain-id`: Network chain ID
- `-gas-price`: Gas price in wei
- `-gas-limit`: Gas limit per transaction

## Monitoring

### Grafana Dashboard

The performance dashboard includes:
- Transaction throughput (TPS)
- Txpool status (pending/queued)
- Block production rate
- Gas utilization
- Per-node metrics

### Txpool Exporter

Custom Python exporter collecting metrics from all 8 nodes:
- `txpool_pending_transactions{node="el-N"}`
- `txpool_queued_transactions{node="el-N"}`

## Pre-funded Accounts

The testnet includes 21 pre-funded genesis accounts. First 5:

```
0x8943545177806ED17B9F23F0a21ee5948eCaa776 (bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31)
0xE25583099BA105D9ec0A67f5Ae86D90e50036425 (39725efee3fb28614de3bacaffe4cc4bd8c436257e2c8bb887c4b5c4be45e76d)
0x614561D2d143621E126e87831AEF287678B442b8 (53321db7c1e331d93a11a41d16f004d7ff63972ec8ec7c25db329728ceeb1710)
0xf93Ee4Cf8c6c40b329b0c0626F28333c132CF241 (ab63b23eb7941c1251757e24b3d2350d2bc05c3c388d06f8fe6feafefb1e8c70)
0x802dCbE1B1A97554B4F50DB5119E37E8e7336417 (5d2344259f42259f82d2c140aa66102ba89b57b4883ee441a8b312622bd42491)
```

## Cleanup

### Stop Services

```bash
ssh -i ~/.ssh/sonicKey.pem ubuntu@CHAIN_IP "kurtosis enclave rm my-testnet --force"
```

### Destroy Infrastructure

```bash
cd terraform
terraform destroy
```

## Troubleshooting

### Check Chain Status

```bash
ssh -i ~/.ssh/sonicKey.pem ubuntu@CHAIN_IP
kurtosis enclave inspect my-testnet
```

### View Logs

```bash
# Reth logs
docker logs el-1-reth-lighthouse--<ID>

# Txpool exporter logs
journalctl -u txpool-exporter -f
```

### Check Txpool

```bash
curl -X POST http://CHAIN_IP:PORT \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}'
```

## Project Structure

```
.
├── deploy.sh                    # Main deployment script
├── network_params.yaml          # Network configuration
├── terraform/                   # Infrastructure as code
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── ansible/                     # Configuration management
│   ├── playbook.yml
│   ├── tps-test-v2.go          # TPS testing tool
│   └── addresses.json          # Test accounts
├── txpool-exporter.py          # Prometheus exporter
└── performance-dashboard-v2.json  # Grafana dashboard
```

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.
