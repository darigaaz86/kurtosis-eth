# Ethereum Testnet on Kubernetes with Kurtosis

This directory contains everything needed to deploy an Ethereum testnet on Kubernetes using Kurtosis.

## Overview

This deployment uses:
- **Kurtosis**: For packaging and orchestrating the Ethereum testnet
- **Kubernetes**: For container orchestration and resource management
- **Ethereum Package**: The ethpandaops/ethereum-package for testnet configuration

## Architecture

```
Kubernetes Cluster
├── Kurtosis Cloud Controller (manages enclaves)
├── Ethereum Enclave
│   ├── 8x Reth (Execution Layer)
│   ├── 8x Lighthouse (Consensus Layer)
│   └── 4x Validator Clients (256 validators total)
└── Monitoring Stack
    ├── Prometheus
    ├── Grafana
    └── Tempo (optional)
```

## Prerequisites

### Required Tools
- `kubectl` - Kubernetes CLI
- `helm` - Kubernetes package manager
- `kurtosis` - Kurtosis CLI
- AWS CLI (if using EKS) or equivalent for your cloud provider

### Cluster Requirements
- **Nodes**: 3+ worker nodes
- **Instance Type**: c5.4xlarge or equivalent (16 vCPU, 32GB RAM)
- **Storage**: 500GB+ per node
- **Kubernetes Version**: 1.24+

## Quick Start

### 1. Set Up Kubernetes Cluster

#### Option A: AWS EKS
```bash
# Create EKS cluster
cd terraform-eks
terraform init
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name ethereum-testnet --region us-east-1
```

#### Option B: Existing Cluster
```bash
# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### 2. Install Kurtosis on Kubernetes

```bash
# Add Kurtosis Helm repository
helm repo add kurtosis https://helm.kurtosis.com
helm repo update

# Install Kurtosis Cloud Controller
helm install kurtosis-cloud kurtosis/kurtosis-cloud \
  --namespace kurtosis-cloud \
  --create-namespace \
  --values kurtosis-values.yaml

# Verify installation
kubectl get pods -n kurtosis-cloud
```

### 3. Configure Kurtosis CLI

```bash
# Set Kubernetes as the backend
kurtosis cluster set kubernetes

# Verify connection
kurtosis cluster ls
```

### 4. Deploy Ethereum Testnet

```bash
# Deploy using the provided configuration
kurtosis run github.com/ethpandaops/ethereum-package \
  --args-file network-params.yaml \
  --enclave eth-testnet

# Monitor deployment
kurtosis enclave inspect eth-testnet
```

### 5. Access Services

```bash
# Get service endpoints
kubectl get svc -n eth-testnet

# Access Grafana
kubectl port-forward -n eth-testnet svc/grafana 3000:3000
# Open http://localhost:3000 (admin/admin)

# Access RPC endpoint
export RPC_URL=$(kubectl get svc -n eth-testnet reth-rpc -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://$RPC_URL:8545
```

## Configuration

### Network Parameters

Edit `network-params.yaml` to customize:
- Number of nodes
- Client types (Reth, Geth, Besu, etc.)
- Validator distribution
- Network parameters (chain ID, slot time, etc.)
- Monitoring options

### Resource Allocation

Edit `kurtosis-values.yaml` to configure:
- CPU and memory limits
- Storage sizes
- Node affinity rules
- Resource quotas

## Operations

### Scaling

```bash
# Add more validator nodes
kurtosis service add eth-testnet validator-5 \
  --image sigp/lighthouse:latest

# Scale existing deployment
kubectl scale deployment reth-node-1 --replicas=2 -n eth-testnet
```

### Monitoring

```bash
# View logs
kubectl logs -f -n eth-testnet deployment/reth-node-1

# Check metrics
kubectl port-forward -n eth-testnet svc/prometheus 9090:9090
# Open http://localhost:9090
```

### Backup

```bash
# Create volume snapshot
kubectl apply -f backup/volume-snapshot.yaml

# Backup validator keys
kubectl cp eth-testnet/validator-1:/keys ./backup/keys-$(date +%Y%m%d)
```

### Cleanup

```bash
# Remove enclave (keeps PVCs)
kurtosis enclave rm eth-testnet

# Delete everything including storage
kubectl delete namespace eth-testnet
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n eth-testnet

# View pod events
kubectl describe pod <pod-name> -n eth-testnet

# Check logs
kubectl logs <pod-name> -n eth-testnet
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n eth-testnet

# Check storage class
kubectl get storageclass

# View PV details
kubectl describe pv <pv-name>
```

### Network Issues

```bash
# Test pod-to-pod connectivity
kubectl exec -it <pod-name> -n eth-testnet -- ping <other-pod-ip>

# Check network policies
kubectl get networkpolicies -n eth-testnet

# View service endpoints
kubectl get endpoints -n eth-testnet
```

### Genesis Not Triggering

```bash
# Check genesis generator logs
kubectl logs -n eth-testnet -l app=genesis-generator

# Verify genesis files
kubectl exec -it <beacon-pod> -n eth-testnet -- ls -la /genesis

# Check beacon node logs
kubectl logs -f -n eth-testnet deployment/lighthouse-beacon-1
```

## Performance Tuning

### Resource Optimization

```yaml
# Adjust in network-params.yaml
participants:
  - el_type: reth
    el_extra_params:
      - "--max-outbound-peers=50"
      - "--max-inbound-peers=50"
    cl_extra_params:
      - "--target-peers=50"
```

### Storage Optimization

```bash
# Use faster storage class
kubectl patch pvc reth-node-1-data -n eth-testnet \
  -p '{"spec":{"storageClassName":"fast-ssd"}}'
```

### Network Optimization

```yaml
# Add pod anti-affinity
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - reth
      topologyKey: kubernetes.io/hostname
```

## Cost Optimization

### Use Spot Instances

```bash
# Add spot instance node group (EKS)
eksctl create nodegroup \
  --cluster ethereum-testnet \
  --name spot-nodes \
  --node-type c5.4xlarge \
  --nodes 3 \
  --spot
```

### Storage Optimization

```bash
# Use cheaper storage for archival data
kubectl patch pvc old-data -n eth-testnet \
  -p '{"spec":{"storageClassName":"standard"}}'
```

## Security

### Network Policies

```bash
# Apply network policies
kubectl apply -f security/network-policies.yaml
```

### Pod Security

```bash
# Apply pod security standards
kubectl label namespace eth-testnet \
  pod-security.kubernetes.io/enforce=restricted
```

### Secrets Management

```bash
# Create secret for validator keys
kubectl create secret generic validator-keys \
  --from-file=keys/ \
  -n eth-testnet
```

## Advanced Topics

### Multi-Region Deployment

Deploy nodes across multiple regions for geo-distribution and resilience.

### GitOps Integration

Use ArgoCD or Flux for declarative, Git-based deployments.

### Service Mesh

Integrate Istio for advanced traffic management and observability.

### Auto-Scaling

Implement HorizontalPodAutoscaler for dynamic scaling based on load.

## Support

- **Kurtosis Docs**: https://docs.kurtosis.com/k8s/
- **Ethereum Package**: https://github.com/ethpandaops/ethereum-package
- **Issues**: File issues in the repository

## License

MIT License - see LICENSE file for details
