#!/usr/bin/env python3
"""
Txpool Prometheus Exporter
Exports Ethereum txpool metrics to Prometheus
"""
import json
import time
import requests
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

# Configuration - Will be updated by Ansible with actual RPC ports
RPC_URLS = [
    "http://127.0.0.1:32769",
    "http://127.0.0.1:32774",
    "http://127.0.0.1:32779",
    "http://127.0.0.1:32784",
    "http://127.0.0.1:32789",
    "http://127.0.0.1:32794",
    "http://127.0.0.1:32799",
    "http://127.0.0.1:32804"
]
EXPORTER_PORT = 9200
UPDATE_INTERVAL = 5  # seconds

# Global metrics storage
metrics = {
    "pending": {},
    "queued": {}
}

def get_txpool_status(rpc_url):
    """Get txpool status from RPC endpoint"""
    try:
        response = requests.post(
            rpc_url,
            json={"jsonrpc": "2.0", "method": "txpool_status", "params": [], "id": 1},
            timeout=5
        )
        result = response.json().get("result", {})
        return {
            "pending": int(result.get("pending", "0x0"), 16),
            "queued": int(result.get("queued", "0x0"), 16)
        }
    except Exception as e:
        print(f"Error fetching txpool from {rpc_url}: {e}")
        return {"pending": 0, "queued": 0}

def update_metrics():
    """Update metrics from all RPC endpoints"""
    global metrics
    while True:
        for idx, rpc_url in enumerate(RPC_URLS):
            status = get_txpool_status(rpc_url)
            metrics["pending"][f"el-{idx+1}"] = status["pending"]
            metrics["queued"][f"el-{idx+1}"] = status["queued"]
        time.sleep(UPDATE_INTERVAL)

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            
            # Generate Prometheus metrics
            output = []
            output.append("# HELP txpool_pending_transactions Number of pending transactions in txpool")
            output.append("# TYPE txpool_pending_transactions gauge")
            for node, count in metrics["pending"].items():
                output.append(f'txpool_pending_transactions{{node="{node}"}} {count}')
            
            output.append("# HELP txpool_queued_transactions Number of queued transactions in txpool")
            output.append("# TYPE txpool_queued_transactions gauge")
            for node, count in metrics["queued"].items():
                output.append(f'txpool_queued_transactions{{node="{node}"}} {count}')
            
            output.append("# HELP txpool_total_transactions Total transactions in txpool")
            output.append("# TYPE txpool_total_transactions gauge")
            for node in metrics["pending"].keys():
                total = metrics["pending"].get(node, 0) + metrics["queued"].get(node, 0)
                output.append(f'txpool_total_transactions{{node="{node}"}} {total}')
            
            self.wfile.write("\n".join(output).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == "__main__":
    # Start metrics updater thread
    updater = threading.Thread(target=update_metrics, daemon=True)
    updater.start()
    
    # Start HTTP server
    server = HTTPServer(("0.0.0.0", EXPORTER_PORT), MetricsHandler)
    print(f"Txpool exporter running on port {EXPORTER_PORT}")
    print(f"Monitoring {len(RPC_URLS)} RPC endpoints")
    server.serve_forever()
