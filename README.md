# Boulder Kubernetes Deployment

A complete Kubernetes deployment for Boulder ACME Certificate Authority, transforming Boulder from Docker Compose to a production-ready, scalable Kubernetes environment.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Important: OCSP Exclusion](#important-ocsp-exclusion)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Testing](#testing)
- [ACME API Usage](#acme-api-usage)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Overview

[Boulder](https://github.com/letsencrypt/boulder) is the ACME Certificate Authority software that powers [Let's Encrypt](https://letsencrypt.org/), the world's largest certificate authority. Boulder implements the ACME protocol (RFC 8555) to provide automated certificate issuance and management for TLS certificates.

This project provides a complete Kubernetes deployment of Boulder's microservice architecture, converting from the traditional Docker Compose setup to a scalable, production-ready Kubernetes environment with proper service dependencies, health checks, and comprehensive testing.

### Why Kubernetes?

- **Scalability**: Independent scaling of Boulder microservices based on load
- **High Availability**: Multi-instance deployments with automatic failover
- **Resource Management**: Efficient resource allocation and limits per service
- **Service Discovery**: Kubernetes-native service discovery replaces Consul
- **Health Monitoring**: Built-in health checks and readiness probes
- **Configuration Management**: Centralized configuration via ConfigMaps and Secrets
- **Production Ready**: Full integration test suite and deployment automation

## Features

✅ **Complete Implementation** - All Boulder services deployed and tested
✅ **Infrastructure Services** - MariaDB, Redis, ProxySQL with persistent storage
✅ **Service Dependencies** - Proper startup ordering with init containers
✅ **Health Monitoring** - Comprehensive health checks for all services
✅ **Integration Testing** - Full ACME workflow validation
✅ **Certificate Management** - Automated PKI hierarchy generation
✅ **Load Balancing** - Multi-instance services with Kubernetes load balancing
✅ **Configuration Management** - Environment-specific configuration support
✅ **Deployment Automation** - One-command deployment and testing scripts

## Important: OCSP Exclusion

**⚠️ CRITICAL NOTICE**: This Kubernetes implementation **excludes all OCSP-related functionality** as it is deprecated in Boulder and slated for removal.

### Excluded OCSP Services

The following Boulder OCSP services are **NOT** included in this deployment:

- **OCSP Responder** - HTTP service for OCSP status requests
- **OCSP Generator** - Background service generating OCSP responses
- **OCSP Updater** - Service updating OCSP response data
- **Akamai Purger** - CDN purging service for OCSP responses

### Why OCSP is Excluded

1.  **Officially Deprecated** - OCSP functionality is deprecated upstream in Boulder
2.  **Planned Removal** - OCSP services are scheduled for complete removal
3.  **Modern Alternatives** - Certificate Transparency (CT) logs provide better transparency
4.  **Simplified Operations** - Reduces deployment complexity and maintenance overhead

**Note**: This exclusion does not impact core ACME certificate issuance functionality.

## Project Structure

```
boulder-k8s/
├── README.md                           # This file
├── Makefile                            # Build and maintenance targets
├── kind-config.yaml                    # Local cluster configuration
├── k8s/                                # Kubernetes manifests and scripts
│   ├── deployments/                    # Service deployments
│   │   ├── infrastructure/             # MariaDB, Redis, ProxySQL
│   │   └── boulder/                    # Boulder services
│   ├── services/                       # Kubernetes services
│   ├── secrets/                        # Secret configurations
│   ├── jobs/                           # Integration test jobs
│   ├── namespaces/                     # Namespace definitions
│   └── scripts/                        # Deployment and test scripts
│       ├── deploy.sh                   # Main deployment script
│       ├── health-check.sh             # Service health validation
│       └── run-integration-tests.sh    # Integration test execution
├── architecture/                       # Architecture documentation
│   ├── overview.md                     # System design overview
│   ├── service-matrix.md               # Detailed service specs
│   └── implementation-plan.md          # Implementation strategy
└── scripts/                            # Utility scripts
    └── lint.sh                         # Code quality validation
```

## Prerequisites

### Required Tools

The following tools are required for deployment and development:

#### Container and Kubernetes Tools
- **Docker Engine** - Container runtime for building and running services
- **kubectl** - Kubernetes command-line tool (v1.25+)
- **kind** - Kubernetes in Docker for local clusters (v0.17+)

#### Development Tools
- **Go** (1.21+) - For building Boulder and running integration tests
- **Python** (3.8+) - For Boulder's integration test framework
- **Git** - Version control with submodule support

#### Validation Tools
- **kubeconform** - Kubernetes manifest validation (preferred)
- **yamllint** - YAML file validation
- **shellcheck** - Shell script validation
- **markdownlint** - Documentation validation
- **jq** - JSON parsing for debugging and configuration management

### System Requirements

- **CPU**: 4+ cores recommended for local development
- **Memory**: 8GB+ RAM for full Boulder deployment
- **Storage**: 20GB+ available disk space
- **Network**: Internet access for external dependencies

### Quick Installation

Install all development dependencies:

```bash
# Using Homebrew (macOS/Linux)
brew bundle

# Or install individual tools
brew install docker kubectl kind go python3
brew install kubeconform yamllint shellcheck markdownlint-cli jq
```

## Deployment

### 1. Prepare Environment

```bash
# Clone repository
git clone <repository-url>
cd boulder-k8s

# Initialize submodules
git submodule update --init --recursive

# Verify prerequisites
make lint
```

### 2. Create Kubernetes Cluster

```bash
# Create kind cluster with custom configuration
kind create cluster --name boulder-k8s --config kind-config.yaml

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### 3. Deploy Boulder Services

```bash
# One-command deployment
./k8s/scripts/deploy.sh

# Monitor deployment progress
kubectl get pods -n boulder -w
```

### 4. Validate Deployment

```bash
# Run health checks
./k8s/scripts/health-check.sh --verbose

# Check ACME API
curl -s http://localhost:4001/directory | jq .
```

## Testing

This project includes comprehensive testing at multiple levels.

### Health Checks

Validate that all Boulder services are running correctly and can communicate with their dependencies.

```bash
# Run basic health check
./k8s/scripts/health-check.sh

# Run with verbose output and resource usage
./k8s/scripts/health-check.sh --verbose --resources
```

### Integration Tests

Run Boulder's complete integration test suite to validate the end-to-end ACME workflow.

```bash
# Run integration tests
./k8s/scripts/run-integration-tests.sh

# Monitor test progress
kubectl logs -f job/boulder-integration-test -n boulder
```

### Manual Testing with an ACME Client

You can manually test the deployment using an ACME client like `certbot`.

```bash
# Register ACME account
certbot register \
    --server http://localhost:4001/acme/directory \
    --email test@example.com \
    --agree-tos \
    --no-eff-email

# Request certificate (HTTP-01 challenge)
certbot certonly \
    --server http://localhost:4001/acme/directory \
    --standalone \
    --domains test.example.com
```

## ACME API Usage

### API Endpoints

The primary endpoint for interacting with the Boulder ACME server is the directory URL.

- **Development URL**: `http://localhost:4001/directory`

This endpoint provides the URLs for all other ACME operations, such as creating a new account, submitting a new order, and revoking a certificate.

### Client Examples

#### Using Certbot

**Account Registration:**
```bash
certbot register \
  --server http://localhost:4001/acme/directory \
  --email admin@example.com \
  --agree-tos \
  --no-eff-email
```

**Certificate Issuance (HTTP-01):**
```bash
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --standalone \
  --domains example.com
```

**Certificate Issuance (DNS-01):**
```bash
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --manual \
  --preferred-challenges dns \
  --domains example.com
```

#### Using acme.sh

**Certificate Issuance (HTTP-01):**
```bash
acme.sh --issue \
  --server http://localhost:4001/acme/directory \
  --domain example.com \
  --standalone
```

**Wildcard Certificate (DNS-01):**
```bash
acme.sh --issue \
  --server http://localhost:4001/acme/directory \
  --domain "*.example.com" \
  --dns dns_manual
```

## Configuration

### Service Configuration

Boulder services use JSON configuration files converted to Kubernetes ConfigMaps:

- **Service Discovery**: Consul SRV lookups replaced with Kubernetes DNS names
- **Database Access**: Connection strings stored in Secrets
- **mTLS Certificates**: Internal PKI mounted as Secret volumes
- **WebPKI Certificates**: CA signing certificates mounted for certificate issuance

### PKI Certificate Management

The deployment automatically manages two certificate hierarchies:

1.  **WebPKI Hierarchy** - For certificate issuance operations
2.  **Internal PKI** - For secure service-to-service communication

Certificates are generated using Boulder's existing certificate generation scripts and mounted as Kubernetes Secrets.

## Troubleshooting

For common issues and solutions, please refer to the [TROUBLESHOOTING.md](TROUBLESHOOTING.md) guide.

## Contributing

### Development Workflow

1.  **Follow Standards**: Implement according to [AGENTS.md](AGENTS.md) guidelines
2.  **Test Thoroughly**: Ensure all integration tests pass
3.  **Document Changes**: Update relevant documentation
4.  **Lint Code**: Run `make lint` before submitting changes

## License

This project follows Boulder's licensing. See the Boulder repository for license details.