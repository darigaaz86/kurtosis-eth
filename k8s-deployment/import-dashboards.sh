#!/bin/bash
# Import Grafana dashboards for Ethereum testnet monitoring

set -e

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

# Check if port-forward is needed
if ! curl -s "$GRAFANA_URL" > /dev/null 2>&1; then
    echo "Starting port-forward to Grafana..."
    kubectl port-forward -n kt-eth-testnet svc/grafana 3000:3000 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    
    # Cleanup on exit
    trap "kill $PORT_FORWARD_PID 2>/dev/null || true" EXIT
fi

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
for i in {1..30}; do
    if curl -s "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Add Prometheus-TxPool as data source
echo "Adding Prometheus-TxPool data source..."
curl -s -X POST "$GRAFANA_USER:$GRAFANA_PASS@${GRAFANA_URL#http://}/api/datasources" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus-TxPool",
    "type": "prometheus",
    "url": "http://prometheus-txpool:9090",
    "access": "proxy",
    "isDefault": false
  }' > /dev/null 2>&1 || echo "Data source may already exist"

# Import performance dashboard if it exists
if [ -f "../performance-dashboard-v2.json" ]; then
    echo "Importing performance dashboard..."
    curl -s -X POST "$GRAFANA_USER:$GRAFANA_PASS@${GRAFANA_URL#http://}/api/dashboards/db" \
      -H "Content-Type: application/json" \
      -d @../performance-dashboard-v2.json > /dev/null 2>&1 || echo "Dashboard may already exist"
fi

echo "✓ Dashboard import completed"
