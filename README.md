# Boulder CA Development Kubernetes Cluster

This repository provides Infrastructure-as-Code (IaC) to set up a local Kubernetes cluster using KinD (Kubernetes in Docker) for Boulder Certificate Authority development and CI environments.

## Overview

Boulder is a Certificate Authority implementation consisting of several microservices. This cluster provides the foundational infrastructure to host Boulder's microservices including:

- Web Front End (WFE)
- Registration Authority (RA)
- Validation Authority (VA)
- Certificate Authority (CA)
- Storage Authority (SA)
- Supporting services (MariaDB, Redis, Consul)

## Prerequisites

Before using these scripts, ensure you have the following installed:

### Required Tools

1. **Docker** - Container runtime
   - Linux: Follow [Docker Engine installation guide](https://docs.docker.com/engine/install/)
   - macOS: Install [Docker Desktop](https://docs.docker.com/desktop/mac/install/)
   - Windows: Install [Docker Desktop](https://docs.docker.com/desktop/windows/install/)

2. **kubectl** - Kubernetes command-line tool
   ```bash
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

   # macOS
   brew install kubectl

   # Windows
   choco install kubernetes-cli
   ```

3. **KinD** - Kubernetes in Docker
   ```bash
   # Linux
   curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
   chmod +x ./kind
   sudo mv ./kind /usr/local/bin/kind

   # macOS
   brew install kind

   # Windows
   choco install kind
   ```

### System Requirements

- **Architecture**: Compatible with amd64 (Linux/Windows) and arm64 (macOS Apple Silicon)
- **Memory**: At least 4GB RAM available for Docker
- **Disk**: At least 10GB free disk space
- **Network**: Internet access for pulling container images

## Usage

### Creating the Cluster

To create a new Boulder development cluster:

```bash
./create-cluster.sh
```

This script will:
- Check for required prerequisites (Docker, kubectl, KinD)
- Delete any existing cluster with the same name
- Create a new cluster using the configuration in `kind-config.yaml`
- Wait for all nodes to be ready
- Display cluster information and status

### Deleting the Cluster

To delete the cluster and clean up resources:

```bash
./delete-cluster.sh
```

This script will:
- Check if the cluster exists
- Delete the cluster and all associated resources
- Confirm successful deletion

### Cluster Configuration

The cluster is configured with:

- **Name**: `boulder-dev-ci`
- **Topology**: 1 control-plane node + 2 worker nodes
- **Networking**: Default KinD CNI (Kindnet)
  - Pod subnet: `10.244.0.0/16`
  - Service subnet: `10.96.0.0/12`
- **Port Mappings**: HTTP (80) and HTTPS (443) forwarded to control-plane
- **Ingress Ready**: Control-plane node labeled for ingress controller deployment

## Verification

After cluster creation, verify the setup:

```bash
# Check cluster info
kubectl cluster-info

# Verify all nodes are ready
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# Switch to the cluster context (if needed)
kubectl config use-context kind-boulder-dev-ci
```

## Architecture

The cluster provides a foundation for Boulder CA microservices deployment with:

- **Control Plane**: Manages the Kubernetes API and cluster state
- **Worker Nodes**: Host application workloads and Boulder microservices
- **Network**: Isolated pod and service networks with external access
- **Storage**: Local storage for development and testing

## Next Steps

Once the cluster is running, you can:

1. Deploy Boulder microservices using Kubernetes manifests
2. Set up persistent storage for MariaDB and other stateful services
3. Configure ingress controllers for external access
4. Deploy monitoring and logging solutions
5. Set up CI/CD pipelines for automated testing

## Troubleshooting

### Common Issues

**Docker not running:**
```bash
# Start Docker service (Linux)
sudo systemctl start docker

# Or start Docker Desktop (macOS/Windows)
```

**Insufficient resources:**
- Increase Docker memory allocation to at least 4GB
- Free up disk space (at least 10GB required)

**Port conflicts:**
- Ensure ports 80, 443, and 6443 are not in use
- Stop other local services using these ports

**Network issues:**
- Check internet connectivity for image pulls
- Verify Docker can access external registries

### Getting Help

If you encounter issues:

1. Check the script output for specific error messages
2. Verify all prerequisites are installed and working
3. Ensure Docker daemon is running and accessible
4. Check available system resources (memory, disk space)

## Contributing

This infrastructure is designed to be extended for Boulder CA development needs. Feel free to modify the configuration for specific requirements while maintaining compatibility with the base Boulder architecture.
