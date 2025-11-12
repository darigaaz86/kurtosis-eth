#!/bin/bash
set -e

echo "🔄 Restarting Ethereum Testnet Chain"
echo "====================================="
echo ""
echo "⚠️  WARNING: This will delete all existing chain data!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "🗑️  Step 1: Removing Terraform-managed NodePort services..."
cd "$(dirname "$0")/terraform-eks"
if [ -f "rpc-nodeports.tf" ]; then
    # Temporarily rename the file to prevent recreation
    mv rpc-nodeports.tf rpc-nodeports.tf.bak
    terraform apply -auto-approve
    echo "✅ NodePort services removed"
fi
cd ..

echo ""
echo "🗑️  Step 2: Deleting namespace and all resources..."
kubectl delete namespace kt-eth-testnet --wait=true

echo ""
echo "⏳ Waiting for namespace to be fully deleted..."
sleep 10

echo ""
echo "🚀 Step 3: Deploying new testnet..."
./deploy-k8s.sh

echo ""
echo "⏳ Step 4: Waiting for chain to initialize (60 seconds)..."
sleep 60

echo ""
echo "📦 Step 5: Deploying additional services..."

# Deploy txpool exporter
echo "  - Deploying txpool exporter..."
kubectl apply -f txpool-exporter-deployment.yaml

# Deploy prometheus-txpool
echo "  - Deploying prometheus-txpool..."
kubectl apply -f prometheus-txpool-sidecar.yaml

# Restore and apply NodePort services
echo "  - Restoring NodePort services..."
cd terraform-eks
if [ -f "rpc-nodeports.tf.bak" ]; then
    mv rpc-nodeports.tf.bak rpc-nodeports.tf
    terraform apply -auto-approve
fi
cd ..

echo ""
echo "⏳ Step 6: Waiting for services to be ready (30 seconds)..."
sleep 30

echo ""
echo "🔧 Step 7: Configuring Grafana datasource..."
kubectl port-forward -n kt-eth-testnet svc/grafana 3000:3000 > /dev/null 2>&1 &
PF_PID=$!
sleep 5

curl -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus-TxPool",
    "type": "prometheus",
    "url": "http://prometheus-txpool:9090",
    "access": "proxy",
    "isDefault": false,
    "jsonData": {"timeInterval": "5s"}
  }' > /dev/null 2>&1

kill $PF_PID 2>/dev/null

echo ""
echo "====================================="
echo "✅ Chain restart complete!"
echo "====================================="
echo ""
echo "Cluster Status:"
kubectl get pods -n kt-eth-testnet | grep -E "NAME|Running" | head -10
echo ""
echo "Access Grafana: kubectl port-forward -n kt-eth-testnet svc/grafana 3000:3000"
echo "Then open: http://localhost:3000 (admin/admin)"
