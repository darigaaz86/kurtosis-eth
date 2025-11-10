# Requirements Document

## Introduction

This document outlines the requirements for deploying the Ethereum testnet using Kurtosis on Kubernetes, following the official Kurtosis K8s documentation. The goal is to leverage Kubernetes orchestration for better scalability, resource management, and operational simplicity compared to the EC2-based deployment.

## Glossary

- **Kurtosis**: A platform for packaging and launching distributed systems in containers
- **Kubernetes (K8s)**: Container orchestration platform for automating deployment, scaling, and management
- **Ethereum Package**: The ethpandaops/ethereum-package Kurtosis package for Ethereum testnets
- **EL**: Execution Layer (Reth, Geth, etc.)
- **CL**: Consensus Layer (Lighthouse, Prysm, etc.)
- **Enclave**: Kurtosis isolated environment for running services
- **Helm**: Kubernetes package manager
- **kubectl**: Kubernetes command-line tool

## Requirements

### Requirement 1: Kubernetes Cluster Setup

**User Story:** As a DevOps engineer, I want to set up a Kubernetes cluster that can run Kurtosis enclaves, so that I can deploy Ethereum testnets in a containerized environment.

#### Acceptance Criteria

1. WHEN setting up the cluster, THE System SHALL provision a Kubernetes cluster with at least 3 worker nodes
2. WHEN configuring resources, THE System SHALL allocate minimum 16 CPU cores and 32GB RAM per worker node
3. WHEN installing prerequisites, THE System SHALL install kubectl, helm, and kurtosis CLI tools
4. WHERE cloud provider is AWS, THE System SHALL use EKS with appropriate node groups
5. WHEN cluster is ready, THE System SHALL verify connectivity using kubectl cluster-info

### Requirement 2: Kurtosis Installation on Kubernetes

**User Story:** As a DevOps engineer, I want to install Kurtosis on my Kubernetes cluster, so that I can run Ethereum testnet enclaves.

#### Acceptance Criteria

1. WHEN installing Kurtosis, THE System SHALL add the Kurtosis Helm repository
2. WHEN deploying Kurtosis, THE System SHALL install the kurtosis-cloud-controller using Helm
3. WHEN configuring storage, THE System SHALL set up persistent volume claims for enclave data
4. WHEN installation completes, THE System SHALL verify kurtosis-cloud-controller pod is running
5. WHEN connecting CLI, THE System SHALL configure kurtosis CLI to use the K8s backend

### Requirement 3: Ethereum Package Configuration

**User Story:** As a blockchain developer, I want to configure the Ethereum package parameters, so that I can customize the testnet topology and client mix.

#### Acceptance Criteria

1. WHEN configuring participants, THE System SHALL support defining multiple EL+CL pairs
2. WHEN setting network parameters, THE System SHALL allow customization of genesis time, slot duration, and chain ID
3. WHEN enabling monitoring, THE System SHALL include Prometheus and Grafana in the configuration
4. WHERE MEV is required, THE System SHALL support mev-boost and relay configuration
5. WHEN validating config, THE System SHALL check YAML syntax and required parameters

### Requirement 4: Enclave Deployment

**User Story:** As a blockchain developer, I want to deploy an Ethereum testnet enclave on Kubernetes, so that I can run a fully functional testnet.

#### Acceptance Criteria

1. WHEN deploying enclave, THE System SHALL create a new Kurtosis enclave in the K8s cluster
2. WHEN launching services, THE System SHALL deploy all EL, CL, and validator containers
3. WHEN generating genesis, THE System SHALL create genesis files and distribute to all nodes
4. WHEN starting network, THE System SHALL ensure all nodes peer and sync correctly
5. WHEN deployment completes, THE System SHALL provide service endpoints and access information

### Requirement 5: Service Exposure and Access

**User Story:** As a developer, I want to access the Ethereum testnet services from outside the cluster, so that I can interact with the network and monitoring tools.

#### Acceptance Criteria

1. WHEN exposing RPC, THE System SHALL create LoadBalancer or NodePort services for EL RPC endpoints
2. WHEN exposing monitoring, THE System SHALL make Grafana accessible via ingress or LoadBalancer
3. WHEN accessing services, THE System SHALL provide connection strings and credentials
4. WHERE security is required, THE System SHALL support authentication and TLS
5. WHEN listing services, THE System SHALL show all exposed endpoints with their URLs

### Requirement 6: Resource Management

**User Story:** As a DevOps engineer, I want to manage resource allocation for the testnet, so that I can optimize costs and performance.

#### Acceptance Criteria

1. WHEN setting limits, THE System SHALL define CPU and memory limits for each container
2. WHEN scaling, THE System SHALL support horizontal scaling of validator nodes
3. WHEN monitoring resources, THE System SHALL track CPU, memory, and storage usage
4. WHERE resources are constrained, THE System SHALL apply resource quotas per namespace
5. WHEN optimizing, THE System SHALL support node affinity and pod anti-affinity rules

### Requirement 7: Persistence and State Management

**User Story:** As a blockchain developer, I want to persist blockchain data across pod restarts, so that I don't lose chain state.

#### Acceptance Criteria

1. WHEN creating volumes, THE System SHALL provision persistent volumes for blockchain data
2. WHEN pod restarts, THE System SHALL remount existing volumes to preserve state
3. WHEN backing up, THE System SHALL support volume snapshots for disaster recovery
4. WHERE storage class is specified, THE System SHALL use the appropriate storage backend
5. WHEN cleaning up, THE System SHALL optionally retain or delete persistent volumes

### Requirement 8: Monitoring and Observability

**User Story:** As a DevOps engineer, I want comprehensive monitoring of the testnet, so that I can troubleshoot issues and track performance.

#### Acceptance Criteria

1. WHEN deploying monitoring, THE System SHALL install Prometheus for metrics collection
2. WHEN visualizing metrics, THE System SHALL deploy Grafana with pre-configured dashboards
3. WHEN collecting logs, THE System SHALL aggregate logs from all pods
4. WHERE tracing is enabled, THE System SHALL support distributed tracing with Tempo
5. WHEN alerting, THE System SHALL configure alerts for node failures and performance issues

### Requirement 9: Network Configuration

**User Story:** As a blockchain developer, I want to configure network parameters, so that I can test different scenarios and fork configurations.

#### Acceptance Criteria

1. WHEN setting genesis, THE System SHALL support custom genesis configurations
2. WHEN configuring forks, THE System SHALL enable all forks from genesis or at specific epochs
3. WHEN setting timing, THE System SHALL allow customization of slot time and epoch length
4. WHERE prefunded accounts are needed, THE System SHALL generate accounts with balances
5. WHEN validating network, THE System SHALL verify all nodes are on the same chain

### Requirement 10: Operational Procedures

**User Story:** As a DevOps engineer, I want documented operational procedures, so that I can manage the testnet lifecycle.

#### Acceptance Criteria

1. WHEN deploying, THE System SHALL provide step-by-step deployment instructions
2. WHEN upgrading, THE System SHALL document the upgrade process for client versions
3. WHEN troubleshooting, THE System SHALL include common issues and solutions
4. WHERE cleanup is needed, THE System SHALL provide commands to remove enclaves
5. WHEN scaling, THE System SHALL document how to add or remove nodes
