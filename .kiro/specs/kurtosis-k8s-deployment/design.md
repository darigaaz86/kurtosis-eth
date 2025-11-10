# Design Document: Kurtosis Kubernetes Deployment

## Overview

This design outlines the architecture and implementation approach for deploying the Ethereum testnet using Kurtosis on Kubernetes. The solution leverages Kurtosis Cloud for Kubernetes integration, providing a containerized, scalable alternative to EC2-based deployments.

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │         Kurtosis Cloud Controller                   │    │
│  │  (Manages enclaves and service orchestration)      │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │              Ethereum Enclave                       │    │
│  │                                                      │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐         │    │
│  │  │ EL Node 1│  │ EL Node 2│  │ EL Node N│         │    │
│  │  │  (Reth)  │  │  (Reth)  │  │  (Reth)  │         │    │
│  │  └──────────┘  └──────────┘  └──────────┘         │    │
│  │                                                      │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐         │    │
│  │  │ CL Node 1│  │ CL Node 2│  │ CL Node N│         │    │
│  │  │(Lighthouse)│(Lighthouse)│(Lighthouse)│         │    │
│  │  └──────────┘  └──────────┘  └──────────┘         │    │
│  │                                                      │    │
│  │  ┌──────────┐  ┌──────────┐                        │    │
│  │  │Validator │  │Validator │                        │    │
│  │  │ Client 1 │  │ Client 2 │                        │    │
│  │  └──────────┘  └──────────┘                        │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │           Monitoring Stack                          │    │
│  │                                                      │    │
│  │  ┌────────────┐  ┌──────────┐  ┌──────────┐       │    │
│  │  │ Prometheus │  │ Grafana  │  │  Tempo   │       │    │
│  │  └────────────┘  └──────────┘  └──────────┘       │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │         Persistent Storage (PVCs)                   │    │
│  │  - Blockchain data                                  │    │
│  │  - Validator keys                                   │    │
│  │  - Monitoring data                                  │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    LoadBalancer         LoadBalancer         Ingress
    (RPC Access)         (Grafana)           (Optional)
```

### Components

#### 1. Kubernetes Cluster
- **Platform**: AWS EKS, GKE, or self-managed
- **Node Configuration**:
  - 3+ worker nodes
  - Instance type: c5.4xlarge or equivalent (16 vCPU, 32GB RAM)
  - Storage: 500GB+ per node for blockchain data
- **Networking**: VPC with private subnets, NAT gateway for outbound

#### 2. Kurtosis Cloud Controller
- **Installation**: Helm chart from Kurtosis repository
- **Function**: Manages enclave lifecycle, service discovery, networking
- **Configuration**:
  - Namespace: `kurtosis-cloud`
  - Service account with cluster-admin permissions
  - ConfigMap for cloud-specific settings

#### 3. Ethereum Enclave
- **Namespace**: Dedicated namespace per enclave (e.g., `eth-testnet-1`)
- **Services**:
  - Execution Layer pods (Reth containers)
  - Consensus Layer pods (Lighthouse containers)
  - Validator Client pods
  - Genesis generator (init container)
- **Networking**:
  - ClusterIP services for inter-pod communication
  - LoadBalancer services for external RPC access
  - Network policies for security

#### 4. Storage Architecture
- **Persistent Volumes**:
  - EL data: 200GB per node (gp3 on AWS)
  - CL data: 100GB per node
  - Validator keys: 1GB (encrypted)
- **Storage Class**: Fast SSD-backed storage (gp3, pd-ssd)
- **Backup Strategy**: Volume snapshots, S3 backup for keys

#### 5. Monitoring Stack
- **Prometheus**:
  - Scrapes metrics from all EL/CL pods
  - ServiceMonitor CRDs for auto-discovery
  - 7-day retention
- **Grafana**:
  - Pre-configured dashboards from ethereum-package
  - LoadBalancer service for external access
  - OAuth integration (optional)
- **Tempo**: Distributed tracing for debugging

## Data Models

### Kurtosis Configuration (network_params.yaml)

```yaml
participants:
  - el_type: reth
    el_image: ghcr.io/paradigmxyz/reth:latest
    cl_type: lighthouse
    cl_image: sigp/lighthouse:latest
    count: 8
    el_extra_params: []
    cl_extra_params: []
    validator_count: 64

network_params:
  network_id: "3151908"
  deposit_contract_address: "0x00000000219ab540356cBB839Cbe05303d7705Fa"
  seconds_per_slot: 3
  genesis_delay: 60
  capella_fork_epoch: 0
  deneb_fork_epoch: 0

persistent: true

prometheus_params:
  enabled: true
  
grafana_params:
  enabled: true
```

### Kubernetes Resources

#### Deployment (EL Node)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reth-node-1
  namespace: eth-testnet
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reth
      node-id: "1"
  template:
    spec:
      containers:
      - name: reth
        image: ghcr.io/paradigmxyz/reth:latest
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: reth-node-1-data
```

#### Service (RPC Endpoint)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: reth-rpc
  namespace: eth-testnet
spec:
  type: LoadBalancer
  selector:
    app: reth
  ports:
  - name: http-rpc
    port: 8545
    targetPort: 8545
  - name: ws-rpc
    port: 8546
    targetPort: 8546
```

#### PersistentVolumeClaim
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reth-node-1-data
  namespace: eth-testnet
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 200Gi
```

## Error Handling

### Pod Failures
- **Strategy**: Kubernetes automatic restart with exponential backoff
- **Health Checks**: Liveness and readiness probes on RPC endpoints
- **Alerting**: Prometheus alerts on pod restart count

### Storage Issues
- **Detection**: Monitor PVC usage, alert at 80% capacity
- **Mitigation**: Automatic volume expansion (if supported by storage class)
- **Recovery**: Volume snapshots for rollback

### Network Partitions
- **Detection**: Monitor peer count metrics
- **Mitigation**: Network policies to ensure pod-to-pod connectivity
- **Recovery**: Automatic peer discovery and reconnection

### Genesis Failures
- **Detection**: Init container exit code monitoring
- **Mitigation**: Retry logic with exponential backoff
- **Recovery**: Manual intervention with debug logs

## Testing Strategy

### Unit Tests
- Validate YAML configurations
- Test Kurtosis Starlark functions
- Verify resource calculations

### Integration Tests
- Deploy minimal enclave (2 nodes)
- Verify genesis generation
- Test RPC connectivity
- Validate monitoring stack

### Performance Tests
- Load test with transaction spam
- Measure block production latency
- Monitor resource utilization
- Test scaling (add/remove nodes)

### Chaos Tests
- Kill random pods
- Simulate network partitions
- Test storage failures
- Verify recovery procedures

## Security Considerations

### Network Security
- Network policies to restrict pod-to-pod communication
- Private subnets for worker nodes
- Security groups for LoadBalancers

### Access Control
- RBAC for Kurtosis controller
- Service accounts with minimal permissions
- Secrets for validator keys and JWT tokens

### Data Encryption
- Encrypted persistent volumes
- TLS for external endpoints
- Encrypted secrets in etcd

## Deployment Workflow

### Phase 1: Cluster Setup
1. Provision Kubernetes cluster (EKS/GKE)
2. Configure kubectl access
3. Install Helm
4. Set up storage classes

### Phase 2: Kurtosis Installation
1. Add Kurtosis Helm repository
2. Install kurtosis-cloud-controller
3. Verify controller is running
4. Configure kurtosis CLI

### Phase 3: Configuration
1. Customize network_params.yaml
2. Validate configuration
3. Generate genesis files (if needed)
4. Prepare validator keys

### Phase 4: Deployment
1. Run `kurtosis run` with config
2. Monitor enclave creation
3. Verify all pods are running
4. Check service endpoints

### Phase 5: Validation
1. Test RPC connectivity
2. Verify block production
3. Check monitoring dashboards
4. Run smoke tests

## Operational Procedures

### Scaling
```bash
# Add more validator nodes
kurtosis service add eth-testnet validator-3 --image=sigp/lighthouse:latest

# Scale existing deployment
kubectl scale deployment reth-node-1 --replicas=2 -n eth-testnet
```

### Upgrades
```bash
# Update client version
kubectl set image deployment/reth-node-1 reth=ghcr.io/paradigmxyz/reth:v1.1.0 -n eth-testnet

# Rolling update
kubectl rollout status deployment/reth-node-1 -n eth-testnet
```

### Backup
```bash
# Create volume snapshot
kubectl create -f volume-snapshot.yaml

# Backup validator keys
kubectl cp eth-testnet/validator-1:/keys ./backup/keys
```

### Cleanup
```bash
# Remove enclave
kurtosis enclave rm eth-testnet

# Delete namespace
kubectl delete namespace eth-testnet

# Clean up PVCs (optional)
kubectl delete pvc --all -n eth-testnet
```

## Performance Optimization

### Resource Tuning
- CPU pinning for EL nodes
- Memory limits based on profiling
- I/O optimization with fast storage

### Network Optimization
- Pod anti-affinity for high availability
- Node affinity for co-location
- CNI plugin tuning (Calico, Cilium)

### Storage Optimization
- Use local SSDs for hot data
- Separate volumes for state and logs
- Enable volume snapshots for backups

## Monitoring and Alerting

### Key Metrics
- Block production rate
- Peer count per node
- CPU/Memory utilization
- Storage usage
- RPC latency

### Alerts
- Node down (pod not ready)
- Low peer count (< 3)
- High resource usage (> 80%)
- Storage full (> 90%)
- Block production stopped

### Dashboards
- Network overview (all nodes)
- Node details (per-node metrics)
- Validator performance
- Resource utilization
- Transaction pool stats

## Cost Optimization

### Resource Efficiency
- Right-size instance types
- Use spot instances for non-critical nodes
- Auto-scaling based on load

### Storage Optimization
- Use cheaper storage for archival data
- Implement data retention policies
- Compress old blocks

### Network Optimization
- Use private endpoints to avoid NAT costs
- Optimize data transfer between zones
- Cache frequently accessed data

## Future Enhancements

1. **Multi-Region Deployment**: Deploy nodes across regions for geo-distribution
2. **Auto-Scaling**: Implement HPA for validator clients
3. **GitOps Integration**: Use ArgoCD/Flux for declarative deployments
4. **Service Mesh**: Integrate Istio for advanced traffic management
5. **Observability**: Add OpenTelemetry for comprehensive tracing
