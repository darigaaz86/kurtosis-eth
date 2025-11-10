#!/bin/bash
set -e

# Ethereum Testnet Deployment Script for Kubernetes
# This script automates the deployment of an Ethereum testnet using Kurtosis on K8s

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-ethereum-testnet}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENCLAVE_NAME="${ENCLAVE_NAME:-eth-testnet}"
NETWORK_PARAMS_FILE="${NETWORK_PARAMS_FILE:-network-params.yaml}"

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v kurtosis &> /dev/null; then
        missing_tools+=("kurtosis")
    fi
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi
    
    log_info "All prerequisites satisfied"
}

deploy_eks_cluster() {
    log_info "Deploying EKS cluster..."
    
    cd terraform-eks
    
    terraform init
    terraform plan -out=tfplan
    terraform apply tfplan
    
    log_info "Configuring kubectl..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    
    cd ..
    
    log_info "EKS cluster deployed successfully"
}

verify_cluster() {
    log_info "Verifying cluster connectivity..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_info "Cluster connectivity verified"
    
    log_info "Checking node status..."
    kubectl get nodes
}

install_kurtosis() {
    log_info "Installing Kurtosis Cloud Controller..."
    
    # Add Helm repository
    helm repo add kurtosis https://helm.kurtosis.com || true
    helm repo update
    
    # Install Kurtosis
    helm upgrade --install kurtosis-cloud kurtosis/kurtosis-cloud \
        --namespace kurtosis-cloud \
        --create-namespace \
        --values kurtosis-values.yaml \
        --wait \
        --timeout 10m
    
    log_info "Waiting for Kurtosis controller to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=kurtosis-controller \
        -n kurtosis-cloud \
        --timeout=300s
    
    log_info "Kurtosis Cloud Controller installed successfully"
}

configure_kurtosis_cli() {
    log_info "Configuring Kurtosis CLI..."
    
    # Set Kubernetes as the backend
    kurtosis cluster set kubernetes
    
    # Verify connection
    if ! kurtosis cluster ls &> /dev/null; then
        log_error "Cannot connect to Kurtosis cluster"
        exit 1
    fi
    
    log_info "Kurtosis CLI configured successfully"
}

deploy_ethereum_testnet() {
    log_info "Deploying Ethereum testnet..."
    
    if [ ! -f "$NETWORK_PARAMS_FILE" ]; then
        log_error "Network parameters file not found: $NETWORK_PARAMS_FILE"
        exit 1
    fi
    
    log_info "Using configuration: $NETWORK_PARAMS_FILE"
    
    # Deploy the testnet
    kurtosis run github.com/ethpandaops/ethereum-package \
        --args-file "$NETWORK_PARAMS_FILE" \
        --enclave "$ENCLAVE_NAME"
    
    log_info "Ethereum testnet deployed successfully"
}

get_service_endpoints() {
    log_info "Retrieving service endpoints..."
    
    # Wait for services to get external IPs
    sleep 30
    
    log_info "Service endpoints:"
    kubectl get svc -n "$ENCLAVE_NAME"
    
    # Get RPC endpoint
    RPC_ENDPOINT=$(kubectl get svc -n "$ENCLAVE_NAME" -l app=reth -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    
    if [ "$RPC_ENDPOINT" != "pending" ]; then
        log_info "RPC Endpoint: http://$RPC_ENDPOINT:8545"
        
        # Test RPC
        log_info "Testing RPC endpoint..."
        curl -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "http://$RPC_ENDPOINT:8545" || log_warn "RPC endpoint not ready yet"
    else
        log_warn "RPC endpoint not ready yet. Check with: kubectl get svc -n $ENCLAVE_NAME"
    fi
    
    # Get Grafana endpoint
    GRAFANA_ENDPOINT=$(kubectl get svc -n "$ENCLAVE_NAME" -l app=grafana -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    
    if [ "$GRAFANA_ENDPOINT" != "pending" ]; then
        log_info "Grafana: http://$GRAFANA_ENDPOINT:3000 (admin/admin)"
    else
        log_info "Grafana: kubectl port-forward -n $ENCLAVE_NAME svc/grafana 3000:3000"
    fi
}

show_next_steps() {
    log_info "Deployment complete!"
    echo ""
    echo "Next steps:"
    echo "1. Check enclave status: kurtosis enclave inspect $ENCLAVE_NAME"
    echo "2. View pods: kubectl get pods -n $ENCLAVE_NAME"
    echo "3. View logs: kubectl logs -f -n $ENCLAVE_NAME deployment/reth-node-1"
    echo "4. Access Grafana: kubectl port-forward -n $ENCLAVE_NAME svc/grafana 3000:3000"
    echo "5. Test RPC: curl -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://localhost:8545"
    echo ""
    echo "To clean up:"
    echo "  kurtosis enclave rm $ENCLAVE_NAME"
    echo "  kubectl delete namespace $ENCLAVE_NAME"
}

# Main execution
main() {
    log_info "Starting Ethereum testnet deployment on Kubernetes"
    
    check_prerequisites
    
    # Check if cluster exists
    if ! kubectl cluster-info &> /dev/null; then
        log_info "No existing cluster found. Deploying new EKS cluster..."
        deploy_eks_cluster
    else
        log_info "Using existing Kubernetes cluster"
    fi
    
    verify_cluster
    
    # Check if Kurtosis is installed
    if ! kubectl get namespace kurtosis-cloud &> /dev/null; then
        install_kurtosis
    else
        log_info "Kurtosis already installed"
    fi
    
    configure_kurtosis_cli
    
    # Check if enclave already exists
    if kurtosis enclave inspect "$ENCLAVE_NAME" &> /dev/null; then
        log_warn "Enclave $ENCLAVE_NAME already exists"
        read -p "Do you want to remove it and redeploy? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing enclave..."
            kurtosis enclave rm "$ENCLAVE_NAME"
        else
            log_info "Keeping existing enclave"
            get_service_endpoints
            show_next_steps
            exit 0
        fi
    fi
    
    deploy_ethereum_testnet
    get_service_endpoints
    show_next_steps
}

# Run main function
main "$@"
