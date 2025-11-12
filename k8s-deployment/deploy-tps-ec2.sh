#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Deploying TPS Test EC2 Instance"
echo "=================================="
echo ""

# Configuration
REGION="${AWS_REGION:-ap-southeast-1}"
CLUSTER_NAME="${CLUSTER_NAME:-ethereum-testnet}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.large}"
SSH_KEY_NAME="${SSH_KEY_NAME:-sonicKey}"

echo "Configuration:"
echo "  Region: $REGION"
echo "  Cluster: $CLUSTER_NAME"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  SSH Key: $SSH_KEY_NAME"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not found. Please install terraform.${NC}"
    exit 1
fi

if ! command -v ansible &> /dev/null; then
    echo -e "${RED}❌ Ansible not found. Please install ansible.${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install aws-cli.${NC}"
    exit 1
fi

# Check SSH key exists
if [ ! -f ~/.ssh/${SSH_KEY_NAME}.pem ]; then
    echo -e "${RED}❌ SSH key not found: ~/.ssh/${SSH_KEY_NAME}.pem${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured. Run 'aws configure'${NC}"
    exit 1
fi

# Check EKS cluster exists
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &> /dev/null; then
    echo -e "${RED}❌ EKS cluster '$CLUSTER_NAME' not found in region $REGION${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites met${NC}"
echo ""

# Step 1: Deploy EC2 with Terraform
echo "📦 Step 1: Deploying EC2 instance with Terraform..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/terraform-tps-ec2"

# Update terraform.tfvars
cat > terraform.tfvars <<EOF
region        = "$REGION"
cluster_name  = "$CLUSTER_NAME"
instance_type = "$INSTANCE_TYPE"
key_name      = "$SSH_KEY_NAME"
EOF

# Initialize and apply
terraform init -upgrade > /dev/null 2>&1
terraform apply -auto-approve

# Get outputs
INSTANCE_IP=$(terraform output -raw instance_public_ip)
INSTANCE_ID=$(terraform output -raw instance_id)

echo -e "${GREEN}✅ EC2 instance created${NC}"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP: $INSTANCE_IP"
echo ""

# Wait for instance to be ready
echo "⏳ Waiting for instance to be ready (30 seconds)..."
sleep 30

# Step 2: Setup with Ansible
echo "📦 Step 2: Setting up instance with Ansible..."
cd "$SCRIPT_DIR/tps-test"

# Update inventory
cat > ansible-inventory.ini <<EOF
[tps_test]
tps-ec2 ansible_host=$INSTANCE_IP ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/${SSH_KEY_NAME}.pem

[tps_test:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Test connection
echo "Testing SSH connection..."
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if ansible -i ansible-inventory.ini tps_test -m ping > /dev/null 2>&1; then
        echo -e "${GREEN}✅ SSH connection successful${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo -e "${RED}❌ Failed to connect to instance after $MAX_RETRIES attempts${NC}"
        exit 1
    fi
    echo "Retrying... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 10
done

# Run Ansible playbook
echo "Running Ansible setup..."
ansible-playbook -i ansible-inventory.ini setup-playbook.yml

echo -e "${GREEN}✅ Instance setup complete${NC}"
echo ""

# Final instructions
echo "=================================="
echo -e "${GREEN}🎉 TPS Test EC2 Deployment Complete!${NC}"
echo "=================================="
echo ""
echo "Instance Details:"
echo "  IP Address: $INSTANCE_IP"
echo "  Instance ID: $INSTANCE_ID"
echo "  SSH Key: ~/.ssh/${SSH_KEY_NAME}.pem"
echo ""
echo "Next Steps:"
echo ""
echo "1. SSH to the instance:"
echo "   ssh -i ~/.ssh/${SSH_KEY_NAME}.pem ec2-user@${INSTANCE_IP}"
echo ""
echo "2. Configure AWS credentials on the instance:"
echo "   aws configure"
echo ""
echo "3. Run the TPS test:"
echo "   cd ~/tps-test"
echo "   ./run-tps-test.sh"
echo ""
echo "Custom test parameters:"
echo "   TPS=1000 ./run-tps-test.sh"
echo "   DURATION=600 ./run-tps-test.sh"
echo "   TPS=1000 DURATION=600 ./run-tps-test.sh"
echo ""
echo "To destroy the instance:"
echo "   cd k8s-deployment/terraform-tps-ec2"
echo "   terraform destroy"
echo ""
