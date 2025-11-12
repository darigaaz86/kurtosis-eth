#!/bin/bash
set -e

# Automated Ethereum Testnet Deployment Script for Kubernetes
# This script automates the complete deployment from EKS cluster to running testnet

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-ethereum-testnet}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
ENCLAVE_NAME="${ENCLAVE_NAME:-eth-testnet}"
NETWORK_PARAMS_FILE="${NETWORK_PARAMS_FILE:-../network_params.yaml}"
KURTOSIS_CONFIG_FILE="$HOME/Library/Application Support/kurtosis/kurtosis-config.yml"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v kurtosis &> /dev/null; then
        missing_tools+=("kurtosis")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi
    
    log_info "✓ All prerequisites satisfied"
}

deploy_eks_cluster() {
    log_step "Deploying EKS cluster..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    pushd "$SCRIPT_DIR/terraform-eks" > /dev/null
    
    log_info "Initializing Terraform..."
    terraform init
    
    log_info "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    log_info "Applying Terraform configuration..."
    terraform apply -auto-approve tfplan
    
    log_info "Configuring kubectl..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    
    popd > /dev/null
    
    log_info "✓ EKS cluster deployed successfully"
}

verify_cluster() {
    log_step "Verifying cluster connectivity..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_info "✓ Cluster connectivity verified"
    
    log_info "Checking node status..."
    kubectl get nodes
    
    # Wait for nodes to be ready
    log_info "Waiting for all nodes to be ready..."
    kubectl wait --for=condition=ready node --all --timeout=300s
    
    log_info "✓ All nodes are ready"
}

verify_storage_classes() {
    log_step "Verifying storage classes..."
    
    # Check if gp3 storage class exists
    if kubectl get storageclass gp3 &> /dev/null; then
        log_info "✓ Storage class 'gp3' exists"
    else
        log_warn "Storage class 'gp3' not found. It should be created by Terraform."
    fi
    
    log_info "✓ Storage classes verified"
}

configure_kurtosis_config() {
    log_step "Configuring Kurtosis..."
    
    # Create kurtosis config directory if it doesn't exist
    mkdir -p "$(dirname "$KURTOSIS_CONFIG_FILE")"
    
    # Create or update kurtosis config
    cat > "$KURTOSIS_CONFIG_FILE" << EOF
config-version: 2
should-send-metrics: true
kurtosis-clusters:
  docker:
    type: "docker"
  $CLUSTER_NAME:
    type: "kubernetes"
    config:
      kubernetes-cluster-name: "$CLUSTER_NAME"
      storage-class: "gp3"
      enclave-size-in-megabytes: 10
EOF
    
    log_info "✓ Kurtosis configuration updated"
}

start_kurtosis_gateway() {
    log_step "Starting Kurtosis gateway..."
    
    # Check if gateway is already running
    if pgrep -f "kurtosis gateway" > /dev/null; then
        log_info "✓ Kurtosis gateway already running"
        return 0
    fi
    
    # Start gateway in background
    log_info "Starting gateway in background..."
    nohup kurtosis gateway > /tmp/kurtosis-gateway.log 2>&1 &
    
    # Wait for gateway to start
    sleep 5
    
    if pgrep -f "kurtosis gateway" > /dev/null; then
        log_info "✓ Kurtosis gateway started successfully"
    else
        log_error "Failed to start Kurtosis gateway"
        log_info "Check logs at: /tmp/kurtosis-gateway.log"
        exit 1
    fi
}

deploy_ethereum_testnet() {
    log_step "Deploying Ethereum testnet..."
    
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local PARAMS_PATH="$SCRIPT_DIR/$NETWORK_PARAMS_FILE"
    
    if [ ! -f "$PARAMS_PATH" ]; then
        log_error "Network parameters file not found: $PARAMS_PATH"
        exit 1
    fi
    
    log_info "Using configuration: $PARAMS_PATH"
    
    # Check if enclave already exists
    if kurtosis enclave inspect "$ENCLAVE_NAME" &> /dev/null; then
        log_warn "Enclave $ENCLAVE_NAME already exists"
        read -p "Do you want to remove it and redeploy? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing enclave..."
            kurtosis enclave rm "$ENCLAVE_NAME" --force
        else
            log_info "Keeping existing enclave"
            return 0
        fi
    fi
    
    # Deploy the testnet
    log_info "Running Kurtosis deployment..."
    kurtosis run github.com/ethpandaops/ethereum-package \
        --args-file "$PARAMS_PATH" \
        --enclave "$ENCLAVE_NAME"
    
    log_info "✓ Ethereum testnet deployed successfully"
}

deploy_txpool_exporter() {
    log_step "Deploying txpool exporter..."
    
    local NAMESPACE="kt-$ENCLAVE_NAME"
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warn "Namespace $NAMESPACE not found, skipping exporter deployment"
        return 0
    fi
    
    # Deploy exporter
    log_info "Applying txpool exporter manifests..."
    kubectl apply -f txpool-exporter-deployment.yaml 2>/dev/null || {
        log_warn "Failed to deploy txpool exporter (may already exist)"
        return 0
    }
    
    # Wait for deployment
    log_info "Waiting for exporter to be ready..."
    kubectl wait --for=condition=available --timeout=60s \
        deployment/txpool-exporter -n "$NAMESPACE" 2>/dev/null || {
        log_warn "Txpool exporter deployment timeout (will continue in background)"
    }
    
    log_info "✓ Txpool exporter deployed"
}

import_grafana_dashboards() {
    log_step "Importing Grafana dashboards..."
    
    # Wait a bit for Grafana to be fully ready
    log_info "Waiting for Grafana to be ready..."
    sleep 10
    
    # Run dashboard import script
    if [ -f "./import-dashboards.sh" ]; then
        log_info "Running dashboard import..."
        ./import-dashboards.sh 2>/dev/null || {
            log_warn "Dashboard import had some issues (check manually)"
        }
    else
        log_warn "Dashboard import script not found, skipping"
    fi
    
    log_info "✓ Dashboard import completed"
}

get_service_info() {
    log_step "Retrieving service information..."
    
    # Get enclave info
    log_info "Enclave details:"
    kurtosis enclave inspect "$ENCLAVE_NAME" --full-uuids=false
    
    echo ""
    log_info "Kubernetes resources:"
    kubectl get pods -n "kt-$ENCLAVE_NAME" 2>/dev/null || log_warn "Namespace not found yet"
}

show_access_info() {
    log_step "Access Information"
    
    echo ""
    echo "=========================================="
    echo "  Ethereum Testnet Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Enclave Name: $ENCLAVE_NAME"
    echo ""
    echo "Access Points:"
    echo "  • Grafana Dashboard: Check 'kurtosis enclave inspect $ENCLAVE_NAME' for port"
    echo "  • Prometheus: Check 'kurtosis enclave inspect $ENCLAVE_NAME' for port"
    echo "  • RPC Endpoints: Check 'kurtosis enclave inspect $ENCLAVE_NAME' for ports"
    echo ""
    echo "Useful Commands:"
    echo "  • View enclave: kurtosis enclave inspect $ENCLAVE_NAME"
    echo "  • View logs: kurtosis enclave logs $ENCLAVE_NAME"
    echo "  • View K8s pods: kubectl get pods -n kt-$ENCLAVE_NAME"
    echo "  • Remove enclave: kurtosis enclave rm $ENCLAVE_NAME --force"
    echo ""
    echo "Test RPC (replace PORT with actual port from inspect):"
    echo "  curl -X POST -H 'Content-Type: application/json' \\"
    echo "    --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \\"
    echo "    http://127.0.0.1:PORT"
    echo ""
}

cleanup_on_error() {
    log_error "Deployment failed!"
    log_info "Check logs and try again"
    exit 1
}

# Main execution
main() {
    log_info "=========================================="
    log_info "  Automated Ethereum Testnet Deployment"
    log_info "=========================================="
    echo ""
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: Deploy or verify EKS cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_info "No existing cluster found. Deploying new EKS cluster..."
        deploy_eks_cluster
    else
        log_info "Using existing Kubernetes cluster: $CLUSTER_NAME"
    fi
    
    # Step 3: Verify cluster
    verify_cluster
    
    # Step 4: Verify storage classes
    verify_storage_classes
    
    # Step 5: Configure Kurtosis
    configure_kurtosis_config
    
    # Step 6: Start Kurtosis gateway
    start_kurtosis_gateway
    
    # Step 7: Deploy Ethereum testnet
    deploy_ethereum_testnet
    
    # Step 8: Deploy txpool exporter
    deploy_txpool_exporter
    
    # Step 9: Import Grafana dashboards
    import_grafana_dashboards
    
    # Step 10: Get service info
    get_service_info
    
    # Step 11: Show access information
    show_access_info
    
    log_info "✓ Deployment completed successfully!"
}

# Run main function
main "$@"
