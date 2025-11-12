# Ethereum Testnet on Kubernetes (EKS)

Complete guide for deploying an Ethereum testnet on AWS EKS using Kurtosis.

## Overview

This deployment creates:
- **EKS 1.31 cluster** with 3 c5.2xlarge nodes
- **8 Reth + Lighthouse node pairs** (256 validators total)
- **Prometheus + Grafana** monitoring stack
- **Persistent storage** using EBS CSI driver with gp3 volumes

## Prerequisites

### Required Tools

```bash
# Check if tools are installed
kubectl version --client
terraform version
kurtosis version
aws --version
```

### Install Missing Tools

**macOS:**
```bash
# Kubectl
brew install kubectl

# Terraform
brew install terraform

# Kurtosis
brew install kurtosis-tech/tap/kurtosis

# AWS CLI
brew install awscli
```

### AWS Configuration

1. **Configure AWS credentials:**
```bash
aws configure
```

2. **Verify access:**
```bash
aws sts get-caller-identity
```

3. **Check EIP limits:**
```bash
aws ec2 describe-addresses --region ap-southeast-1
```
> Note: You need at least 1 available Elastic IP. Default limit is 5 per region.

## Quick Start

### Automated Deployment

```bash
cd k8s-deployment
./deploy.sh
```

This script will:
1. ✅ Check prerequisites
2. ✅ Deploy EKS cluster (if not exists)
3. ✅ Verify cluster connectivity
4. ✅ Configure storage classes
5. ✅ Setup Kurtosis configuration
6. ✅ Start Kurtosis gateway
7. ✅ Deploy Ethereum testnet

**Deployment time:** ~15-20 minutes

## Manual Deployment

### Step 1: Deploy EKS Cluster

```bash
cd k8s-deployment/terraform-eks

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name ethereum-testnet --region ap-southeast-1
```

### Step 2: Verify Cluster

```bash
# Check cluster info
kubectl cluster-info

# Check nodes
kubectl get nodes

# Wait for nodes to be ready
kubectl wait --for=condition=ready node --all --timeout=300s
```

### Step 3: Configure Kurtosis

Create or update `~/Library/Application Support/kurtosis/kurtosis-config.yml`:

```yaml
config-version: 2
should-send-metrics: true
kurtosis-clusters:
  docker:
    type: "docker"
  ethereum-testnet:
    type: "kubernetes"
    config:
      kubernetes-cluster-name: "ethereum-testnet"
      storage-class: "gp3"
      enclave-size-in-megabytes: 10
```

### Step 4: Start Kurtosis Gateway

```bash
# Start gateway in background
nohup kurtosis gateway > /tmp/kurtosis-gateway.log 2>&1 &

# Verify it's running
ps aux | grep "kurtosis gateway"
```

### Step 5: Deploy Ethereum Testnet

```bash
cd k8s-deployment

# Deploy using the network parameters
kurtosis run github.com/ethpandaops/ethereum-package \
  --args-file ../network_params.yaml \
  --enclave eth-testnet
```

## Configuration

### Network Parameters

Edit `network_params.yaml` to customize:

```yaml
participants:
  - el_type: reth
    cl_type: lighthouse
    count: 8              # Number of node pairs
    validator_count: 32   # Validators per node

network_params:
  network_id: "3151908"
  seconds_per_slot: 3
  genesis_delay: 20
  # ... more parameters
```

### Terraform Variables

Edit `k8s-deployment/terraform-eks/terraform.tfvars`:

```hcl
aws_region         = "ap-southeast-1"
cluster_name       = "ethereum-testnet"
kubernetes_version = "1.31"

# Node configuration
# instance_types in main.tf: c5.2xlarge (8 vCPU, 16GB RAM)
# min_size: 3, max_size: 5, desired_size: 3
```

## Accessing Services

### View Enclave Information

```bash
kurtosis enclave inspect eth-testnet
```

This shows:
- Service endpoints and ports
- RPC URLs
- Grafana/Prometheus URLs
- Node information

### Access Grafana

```bash
# Get Grafana port from enclave inspect
kurtosis enclave inspect eth-testnet | grep grafana

# Open Grafana
open http://127.0.0.1:<GRAFANA_PORT>

# Default credentials
Username: admin
Password: admin
```

### Import Additional Dashboards

The deployment includes default Ethereum dashboards. To add more:

**Import Performance Dashboard (Custom TPS Testing):**
```bash
./import-performance-dashboard.sh
```

**Import All Popular Dashboards:**
```bash
cd k8s-deployment
./import-dashboards.sh
```

This imports:
- **Ethereum Performance Analysis** (Custom TPS dashboard)
- Kubernetes Cluster Monitoring
- Node Exporter Full
- Ethereum 2.0 Metrics
- Pod Monitoring

See `k8s-deployment/GRAFANA-DASHBOARDS.md` for manual import and customization.

### Access Prometheus

```bash
# Get Prometheus port from enclave inspect
open http://127.0.0.1:<PROMETHEUS_PORT>
```

### Test RPC Endpoint

```bash
# Get RPC port from enclave inspect
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:<RPC_PORT>
```

### View Kubernetes Resources

```bash
# List all pods
kubectl get pods -n kt-eth-testnet

# View logs from a specific node
kubectl logs -f -n kt-eth-testnet -l app=reth

# View all services
kubectl get svc -n kt-eth-testnet
```

## Custom Metrics Exporter

### Deploy Txpool Exporter

The txpool exporter collects transaction pool metrics from all nodes:

```bash
cd k8s-deployment
./deploy-txpool-exporter.sh
```

This deploys a custom exporter that provides:
- `txpool_pending_transactions` - Pending transactions per node
- `txpool_queued_transactions` - Queued transactions per node
- `txpool_total_transactions` - Total transactions per node

The metrics are automatically scraped by Prometheus and available in Grafana.

**View metrics:**
```bash
# Port forward to exporter
kubectl port-forward -n kt-eth-testnet svc/txpool-exporter 9200:9200

# Check metrics
curl http://localhost:9200/metrics
```

## Monitoring

### Check Enclave Status

```bash
kurtosis enclave inspect eth-testnet
```

### View Logs

```bash
# All logs from enclave
kurtosis enclave logs eth-testnet

# Specific service logs
kurtosis service logs eth-testnet el-1-reth-lighthouse
```

### Kubernetes Monitoring

```bash
# Watch pods
kubectl get pods -n kt-eth-testnet -w

# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n kt-eth-testnet
```

## Troubleshooting

### EKS Cluster Issues

**Nodes not joining cluster:**
```bash
# Check node status
kubectl get nodes

# Describe node for events
kubectl describe node <node-name>

# Check EKS addon status
aws eks describe-addon --cluster-name ethereum-testnet \
  --addon-name aws-ebs-csi-driver --region ap-southeast-1
```

**EBS CSI Driver issues:**
```bash
# Check CSI driver pods
kubectl get pods -n kube-system | grep ebs-csi

# View CSI driver logs
kubectl logs -n kube-system deployment/ebs-csi-controller
```

### Kurtosis Issues

**Gateway not connecting:**
```bash
# Check if gateway is running
ps aux | grep "kurtosis gateway"

# Restart gateway
pkill -f "kurtosis gateway"
nohup kurtosis gateway > /tmp/kurtosis-gateway.log 2>&1 &

# Check gateway logs
tail -f /tmp/kurtosis-gateway.log
```

**Enclave deployment fails:**
```bash
# Check enclave status
kurtosis enclave inspect eth-testnet

# View enclave logs
kurtosis enclave logs eth-testnet

# Remove and redeploy
kurtosis enclave rm eth-testnet --force
kurtosis run github.com/ethpandaops/ethereum-package \
  --args-file ../network_params.yaml \
  --enclave eth-testnet
```

### Storage Issues

**PVC not binding:**
```bash
# Check PVCs
kubectl get pvc -n kt-eth-testnet

# Check storage classes
kubectl get storageclass

# Describe PVC for events
kubectl describe pvc <pvc-name> -n kt-eth-testnet
```

### Common Errors

**Error: EIP limit exceeded**
```bash
# List current EIPs
aws ec2 describe-addresses --region ap-southeast-1

# Release unused EIP
aws ec2 release-address --allocation-id <eipalloc-xxx> --region ap-southeast-1
```

**Error: AWS credentials expired**
```bash
# Refresh AWS credentials
aws sso login

# Or reconfigure
aws configure
```

## Cleanup

### Remove Enclave Only

```bash
# Stop enclave but keep cluster
kurtosis enclave rm eth-testnet --force
```

### Full Cleanup

```bash
cd k8s-deployment/terraform-eks

# Destroy all resources
terraform destroy

# Or use automated cleanup (if you created the script)
cd ..
./cleanup.sh
```

**What gets deleted:**
- Kurtosis enclave and all services
- EKS cluster and node groups
- VPC, subnets, NAT gateway
- Security groups
- EBS volumes
- IAM roles

> ⚠️ **Warning:** This is irreversible. All data will be lost.

## Cost Optimization

### Current Configuration Costs (ap-southeast-1)

**Compute:**
- 3x c5.2xlarge nodes: ~$0.34/hour each = ~$1.02/hour
- Total: ~$24.48/day or ~$734/month

**Storage:**
- 3x 300GB gp3 volumes: ~$24/month each = ~$72/month
- EBS snapshots: Variable

**Network:**
- NAT Gateway: ~$0.045/hour = ~$32.40/month
- Data transfer: Variable

**Total estimated cost:** ~$838/month (24/7 operation)

### Cost Reduction Tips

1. **Stop when not in use:**
```bash
# Scale down nodes
kubectl scale deployment --all --replicas=0 -n kt-eth-testnet

# Or destroy cluster
terraform destroy
```

2. **Use smaller instances:**
   - Edit `main.tf`: Change `c5.2xlarge` to `c5.xlarge`
   - Reduces compute cost by 50%

3. **Reduce node count:**
   - Edit `terraform.tfvars`: Set `desired_size = 2`
   - Reduces compute cost by 33%

4. **Use Spot instances:**
   - Edit `main.tf`: Set `capacity_type = "SPOT"`
   - Saves up to 70% on compute

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     AWS EKS Cluster                      │
│                    (Kubernetes 1.31)                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │  │
│  │ c5.2xlarge   │  │ c5.2xlarge   │  │ c5.2xlarge   │  │
│  │ 8vCPU/16GB   │  │ 8vCPU/16GB   │  │ 8vCPU/16GB   │  │
│  │ 300GB gp3    │  │ 300GB gp3    │  │ 300GB gp3    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Kurtosis Enclave: eth-testnet              │ │
│  ├────────────────────────────────────────────────────┤ │
│  │  • 8x Reth (Execution Layer)                       │ │
│  │  • 8x Lighthouse (Consensus Layer)                 │ │
│  │  • 8x Lighthouse (Validator Client)                │ │
│  │  • 256 Validators (32 per node)                    │ │
│  │  • Prometheus (Metrics)                            │ │
│  │  • Grafana (Dashboards)                            │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   Kurtosis Gateway    │
              │   (localhost:9710)    │
              └───────────────────────┘
```

## Technical Details

### EKS Configuration

- **Version:** 1.31
- **AMI:** Amazon Linux 2023 (AL2023_x86_64_STANDARD)
- **Networking:** VPC with public/private subnets across 3 AZs
- **Storage:** EBS CSI driver with gp3 volumes
- **Security:** IMDSv2 enforced, encrypted volumes

### Storage Classes

| Name | Provisioner | Type | IOPS | Throughput | Default |
|------|-------------|------|------|------------|---------|
| gp3 | ebs.csi.aws.com | gp3 | 3000 | 125 MB/s | ✅ |
| fast-ssd | ebs.csi.aws.com | gp3 | 3000 | 125 MB/s | ❌ |
| standard | ebs.csi.aws.com | gp3 | 3000 | 125 MB/s | ❌ |

### Network Configuration

- **Network ID:** 3151908
- **Slot Time:** 3 seconds
- **Genesis Delay:** 20 seconds
- **Validators:** 256 total (32 per node)
- **Forks:** All active from genesis (Deneb, Electra)

## Support

### Useful Links

- [Kurtosis Documentation](https://docs.kurtosis.com/)
- [Ethereum Package](https://github.com/ethpandaops/ethereum-package)
- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Reth Documentation](https://paradigmxyz.github.io/reth/)
- [Lighthouse Documentation](https://lighthouse-book.sigmaprime.io/)

### Getting Help

1. Check logs: `kurtosis enclave logs eth-testnet`
2. Inspect enclave: `kurtosis enclave inspect eth-testnet`
3. Check Kubernetes events: `kubectl get events -n kt-eth-testnet`
4. Review this README's troubleshooting section

## License

This deployment configuration is provided as-is for educational and testing purposes.
