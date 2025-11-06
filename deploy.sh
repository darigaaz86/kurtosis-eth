#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   Ethereum Testnet Deployment Automation                 ║
║   Terraform + Ansible                                     ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

command -v terraform >/dev/null 2>&1 || error "Terraform is not installed. Install from: https://www.terraform.io/downloads"
command -v ansible-playbook >/dev/null 2>&1 || error "Ansible is not installed. Install with: pip install ansible"

success "Prerequisites check passed"

# Step 1: Terraform
log "Step 1: Provisioning EC2 instance with Terraform..."

cd terraform

if [ ! -f "terraform.tfvars" ]; then
    warn "terraform.tfvars not found. Please create it from terraform.tfvars.example"
    error "Copy terraform.tfvars.example to terraform.tfvars and fill in your values"
fi

log "Initializing Terraform..."
terraform init

log "Planning infrastructure..."
terraform plan -out=tfplan

read -p "Do you want to apply this plan? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    error "Deployment cancelled by user"
fi

log "Applying Terraform configuration..."
terraform apply tfplan

success "EC2 instance provisioned successfully"

# Get outputs
CHAIN_IP=$(terraform output -raw chain_public_ip)
TPS_IP=$(terraform output -raw tps_public_ip)
log "Chain Node IP: ${CHAIN_IP}"
log "TPS Node IP: ${TPS_IP}"

cd ..

# Step 2: Wait for instance to be ready
log "Step 2: Waiting for instance to be ready..."
log "This may take 2-3 minutes for cloud-init to complete..."

sleep 30

for i in {1..20}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/*.pem ubuntu@${CHAIN_IP} "echo 'SSH ready'" 2>/dev/null; then
        success "Instance is ready"
        break
    fi
    log "Waiting for SSH... (attempt $i/20)"
    sleep 15
done

# Step 3: Ansible deployment
log "Step 3: Deploying Ethereum testnet with Ansible..."

cd ansible

if [ ! -f "inventory.ini" ]; then
    error "Ansible inventory not generated. Check Terraform outputs."
fi

log "Running Ansible playbook..."
ansible-playbook -i inventory.ini playbook.yml

cd ..

success "Deployment completed successfully!"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Deployment Summary                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Chain Node IP:    ${BLUE}${CHAIN_IP}${NC}"
echo -e "TPS Node IP:      ${BLUE}${TPS_IP}${NC}"
echo ""
echo -e "${GREEN}Services:${NC}"
# Get actual ports
RPC_PORT=$(ssh -i ~/.ssh/*.pem -o StrictHostKeyChecking=no ubuntu@${CHAIN_IP} 'docker ps | grep "el-1-reth" | grep -oP "0\.0\.0\.0:\K[0-9]+(?=->8545)"' 2>/dev/null || echo "8545")
GRAFANA_PORT=$(ssh -i ~/.ssh/*.pem -o StrictHostKeyChecking=no ubuntu@${CHAIN_IP} 'docker ps | grep grafana | grep -oP "0\.0\.0\.0:\K[0-9]+(?=->3000)"' 2>/dev/null || echo "3000")
PROMETHEUS_PORT=$(ssh -i ~/.ssh/*.pem -o StrictHostKeyChecking=no ubuntu@${CHAIN_IP} 'docker ps | grep prometheus | grep -oP "0\.0\.0\.0:\K[0-9]+(?=->9090)"' 2>/dev/null || echo "9090")

echo -e "  RPC Endpoint:     ${BLUE}http://${CHAIN_IP}:${RPC_PORT}${NC}"
echo -e "  Grafana:          ${BLUE}http://${CHAIN_IP}:${GRAFANA_PORT}${NC} (admin/admin)"
echo -e "  Prometheus:       ${BLUE}http://${CHAIN_IP}:${PROMETHEUS_PORT}${NC}"
echo -e "  Txpool Exporter:  ${BLUE}http://${CHAIN_IP}:9200/metrics${NC}"
echo ""
echo -e "${YELLOW}Quick Commands:${NC}"
echo -e "  Run TPS Test:   ${BLUE}./run-tps-test.sh${NC}"
echo -e "  Setup Monitor:  ${BLUE}./setup-monitoring.sh${NC}"
echo -e "  SSH Chain:      ${BLUE}ssh -i ~/.ssh/your-key.pem ubuntu@${CHAIN_IP}${NC}"
echo -e "  SSH TPS:        ${BLUE}ssh -i ~/.ssh/your-key.pem ubuntu@${TPS_IP}${NC}"
echo ""
echo -e "${YELLOW}Monitoring:${NC}"
echo -e "  View Dashboards: Open Grafana and check imported dashboards"
echo -e "  Check Metrics:   ${BLUE}curl http://${CHAIN_IP}:9200/metrics${NC}"
echo ""
echo -e "See ${BLUE}DEPLOYMENT.md${NC} for detailed documentation"
echo ""
