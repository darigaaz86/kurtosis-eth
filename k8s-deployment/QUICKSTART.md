# Quick Start Guide: Ethereum Testnet on Kubernetes

Get your Ethereum testnet running on Kubernetes in under 30 minutes!

## Prerequisites

Install these tools before starting:

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Kurtosis
brew install kurtosis-tech/tap/kurtosis

# AWS CLI (if using EKS)
brew install awscli

# Terraform
brew install terraform
```

## Option 1: Automated Deployment (Recommended)

```bash
# Clone the repository
cd k8s-deployment

# Set your AWS credentials
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1

# Run the deployment script
./deploy.sh
```

That's it! The script will:
1. ✅ Check prerequisites
2. ✅ Deploy EKS cluster (if needed)
3. ✅ Install Kurtosis
4. ✅ Deploy Ethereum testnet
5. ✅ Show service endpoints

## Option 2: Manual Step-by-Step

### Step 1: Deploy EKS Cluster

```bash
cd terraform-eks
terraform init
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name ethereum-testnet --region us-east-1
```

### Step 2: Install Kurtosis

```bash
# Add Helm repo
helm repo add kurtosis https://helm.kurtosis.com
helm repo update

# Install Kurtosis Cloud Controller
helm install kurtosis-cloud kurtosis/kurtosis-cloud \
  --namespace kurtosis-cloud \
  --create-namespace \
  --values kurtosis-values.yaml

# Configure CLI
kurtosis cluster set kubernetes
```

### Step 3: Deploy Testnet

```bash
# Deploy Ethereum testnet
kurtosis run github.com/ethpandaops/ethereum-package \
  --args-file network-params.yaml \
  --enclave eth-testnet

# Check status
kurtosis enclave inspect eth-testnet
```

## Accessing Services

### RPC Endpoint

```bash
# Get RPC endpoint
export RPC_URL=$(kubectl get svc -n eth-testnet -l app=reth -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Test RPC
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://$RPC_URL:8545
```

### Grafana Dashboard

```bash
# Port forward
kubectl port-forward -n eth-testnet svc/grafana 3000:3000

# Open browser
open http://localhost:3000
# Login: admin/admin
```

### Prometheus

```bash
# Port forward
kubectl port-forward -n eth-testnet svc/prometheus 9090:9090

# Open browser
open http://localhost:9090
```

## Common Operations

### View Logs

```bash
# List pods
kubectl get pods -n eth-testnet

# View logs
kubectl logs -f -n eth-testnet deployment/reth-node-1
kubectl logs -f -n eth-testnet deployment/lighthouse-beacon-1
```

### Scale Validators

```bash
# Add more validators
kurtosis service add eth-testnet validator-5 \
  --image sigp/lighthouse:latest
```

### Restart a Service

```bash
# Restart a pod
kubectl rollout restart deployment/reth-node-1 -n eth-testnet
```

### Check Resource Usage

```bash
# Pod resource usage
kubectl top pods -n eth-testnet

# Node resource usage
kubectl top nodes
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n eth-testnet

# Describe pod
kubectl describe pod <pod-name> -n eth-testnet

# Check events
kubectl get events -n eth-testnet --sort-by='.lastTimestamp'
```

### Storage Issues

```bash
# Check PVCs
kubectl get pvc -n eth-testnet

# Check storage class
kubectl get storageclass
```

### Network Issues

```bash
# Test connectivity
kubectl exec -it <pod-name> -n eth-testnet -- ping <other-pod-ip>

# Check services
kubectl get svc -n eth-testnet
```

## Cleanup

### Remove Testnet Only

```bash
# Remove enclave (keeps PVCs)
kurtosis enclave rm eth-testnet

# Or delete namespace (removes everything)
kubectl delete namespace eth-testnet
```

### Remove Everything

```bash
# Remove testnet
kurtosis enclave rm eth-testnet

# Remove Kurtosis
helm uninstall kurtosis-cloud -n kurtosis-cloud

# Destroy EKS cluster
cd terraform-eks
terraform destroy
```

## Cost Estimation

### AWS EKS Costs (us-east-1)

- **EKS Control Plane**: $0.10/hour = ~$73/month
- **Worker Nodes** (3x c5.4xlarge): $0.68/hour each = ~$1,468/month
- **Storage** (1.5TB gp3): ~$120/month
- **Data Transfer**: Variable, ~$50-100/month

**Total**: ~$1,700-1,800/month

### Cost Optimization Tips

1. Use spot instances for non-critical nodes (50-70% savings)
2. Scale down during off-hours
3. Use cheaper storage for archival data
4. Enable cluster autoscaler

## Next Steps

1. **Customize Configuration**: Edit `network-params.yaml` to change node count, client types, etc.
2. **Add Monitoring**: Set up alerts and dashboards
3. **Load Testing**: Use the tx_spammer service to test performance
4. **Security**: Implement network policies and RBAC
5. **GitOps**: Set up ArgoCD for declarative deployments

## Support

- **Kurtosis Docs**: https://docs.kurtosis.com/k8s/
- **Ethereum Package**: https://github.com/ethpandaops/ethereum-package
- **Issues**: File issues in the repository

## Tips

- Use `kubectl get all -n eth-testnet` to see all resources
- Monitor costs with AWS Cost Explorer
- Set up budget alerts in AWS
- Use `kurtosis enclave dump eth-testnet` to export logs
- Enable cluster autoscaler for dynamic scaling

Happy testing! 🚀
