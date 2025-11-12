# Configure Kubernetes provider to manage resources in the EKS cluster
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# NodePort services for RPC endpoints
# These expose the RPC endpoints on node ports so they can be accessed from EC2 instances

locals {
  el_services = [
    "el-1-reth-lighthouse",
    "el-2-reth-lighthouse",
    "el-3-reth-lighthouse",
    "el-4-reth-lighthouse",
    "el-5-reth-lighthouse",
    "el-6-reth-lighthouse",
    "el-7-reth-lighthouse",
    "el-8-reth-lighthouse",
  ]
  
  start_nodeport = 30545
}

# Get the enclave ID from an existing service
data "kubernetes_service_v1" "el_1_service" {
  metadata {
    name      = "el-1-reth-lighthouse"
    namespace = "kt-eth-testnet"
  }
}

locals {
  enclave_id = data.kubernetes_service_v1.el_1_service.spec[0].selector["kurtosistech.com/enclave-id"]
}

resource "kubernetes_service_v1" "rpc_nodeport" {
  for_each = toset(local.el_services)
  
  depends_on = [module.eks, data.kubernetes_service_v1.el_1_service]

  metadata {
    name      = "${each.key}-nodeport"
    namespace = "kt-eth-testnet"
    labels = {
      type = "nodeport-rpc"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      "kurtosistech.com/id" = each.key
      "kurtosistech.com/enclave-id" = local.enclave_id
    }

    port {
      name        = "rpc"
      port        = 8545
      target_port = 8545
      node_port   = local.start_nodeport + index(local.el_services, each.key)
      protocol    = "TCP"
    }
  }
}

# Output the RPC endpoints
output "rpc_nodeport_mappings" {
  description = "Mapping of services to their NodePort numbers"
  value = {
    for service_name in local.el_services :
    service_name => local.start_nodeport + index(local.el_services, service_name)
  }
}

output "rpc_endpoints_for_tps_test" {
  description = "RPC endpoints accessible from EC2 (use any node IP)"
  value = [
    for service_name in local.el_services :
    "http://<NODE_IP>:${local.start_nodeport + index(local.el_services, service_name)}"
  ]
}
