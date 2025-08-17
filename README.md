# Boulder Kubernetes Deployment

A complete Kubernetes deployment for Boulder ACME Certificate Authority, transforming Boulder from Docker Compose to a production-ready, scalable Kubernetes environment.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Important: OCSP Exclusion](#important-ocsp-exclusion)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Testing](#testing)
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

1. **Officially Deprecated** - OCSP functionality is deprecated upstream in Boulder
2. **Planned Removal** - OCSP services are scheduled for complete removal
3. **Modern Alternatives** - Certificate Transparency (CT) logs provide better transparency
4. **Simplified Operations** - Reduces deployment complexity and maintenance overhead

**Note**: This exclusion does not impact core ACME certificate issuance functionality.

## Quick Start

### Prerequisites

Install development dependencies using Homebrew:

```bash
brew bundle
```

Or install individually:
- **Docker** - Container runtime
- **kubectl** - Kubernetes CLI
- **kind** - Local Kubernetes clusters
- **Go 1.21+** - For integration tests
- **Python 3.8+** - For test scripts

### 1. Clone and Initialize

```bash
git clone <repository-url>
cd boulder-k8s
git submodule update --init --recursive
```

### 2. Create Kubernetes Cluster

```bash
kind create cluster --name boulder-k8s --config kind-config.yaml
```

### 3. Deploy Boulder

```bash
./k8s/scripts/deploy.sh
```

### 4. Verify Deployment

```bash
# Check service health
./k8s/scripts/health-check.sh

# Test ACME endpoint  
curl -k http://localhost:4001/directory
```

### 5. Run Integration Tests

```bash
./k8s/scripts/run-integration-tests.sh
```

## Documentation

This project includes comprehensive documentation organized by topic:

### Core Documentation

- **[README.md](README.md)** _(this file)_ - Project overview and quick start
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Detailed deployment guide and procedures
- **[TESTING.md](TESTING.md)** - Testing framework and validation procedures
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[API-USAGE.md](API-USAGE.md)** - ACME protocol usage and examples

### Architecture Documentation

- **[architecture/overview.md](architecture/overview.md)** - System architecture and design
- **[architecture/service-matrix.md](architecture/service-matrix.md)** - Service specifications
- **[architecture/implementation-plan.md](architecture/implementation-plan.md)** - Implementation strategy

### Reference Materials

- **[SPECp1.md](SPECp1.md)** - Phase 1 technical specifications
- **[SPECp2.md](SPECp2.md)** - Phase 2 production enhancements
- **[AGENTS.md](AGENTS.md)** - Development standards and guidelines

## Architecture

Boulder implements a microservice architecture with clear service dependencies:

### Core Services

| Service | Purpose | Replicas | Dependencies |
|---------|---------|----------|--------------|
| **WFE2** | ACME API endpoint | 1 | RA, SA, Nonce Service |
| **Registration Authority** | Certificate workflow orchestration | 2 | SA, CA, VA, Publisher |
| **Certificate Authority** | Certificate signing and issuance | 2 | SA, SCT Provider |
| **Storage Authority** | Database operations | 2 | ProxySQL, MariaDB |
| **Validation Authority** | Domain validation challenges | 2 | SA, Remote VAs |
| **Publisher** | Certificate Transparency submission | 2 | External CT logs |
| **Nonce Service** | Anti-replay protection | 2+ | Redis |

### Infrastructure Services

| Service | Type | Purpose |
|---------|------|---------|
| **MariaDB** | StatefulSet | Primary database with persistent storage |
| **ProxySQL** | Deployment | Database proxy and connection pooling |
| **Redis** | StatefulSet | Rate limiting and nonce storage (2 instances) |

### Service Dependencies

```
Infrastructure → Foundation → Validation → Certificate → Registration → Web
     ↓               ↓           ↓            ↓             ↓          ↓
  MariaDB        →    SA       →    VA    →     CA       →    RA    →  WFE2
  ProxySQL           Publisher      ↑                       ↑        ↑
  Redis       →   Remote VAs    ────┘                       │        │
                                                            │        └→ SFE
                                                            └→ Nonce Service
```

## Project Structure

```
boulder-k8s/
├── README.md                           # This file
├── DEPLOYMENT.md                       # Deployment guide  
├── TESTING.md                          # Testing documentation
├── TROUBLESHOOTING.md                  # Issue resolution guide
├── API-USAGE.md                        # ACME usage examples
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
brew install kubeconform yamllint shellcheck markdownlint-cli
```

## Installation

### Step-by-Step Deployment

#### 1. Prepare Environment

```bash
# Clone repository
git clone <repository-url>
cd boulder-k8s

# Initialize submodules
git submodule update --init --recursive

# Verify prerequisites
make lint
```

#### 2. Create Kubernetes Cluster

```bash
# Create kind cluster with custom configuration
kind create cluster --name boulder-k8s --config kind-config.yaml

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

#### 3. Deploy Boulder Services

```bash
# One-command deployment
./k8s/scripts/deploy.sh

# Monitor deployment progress
kubectl get pods -n boulder -w
```

#### 4. Validate Deployment

```bash
# Run health checks
./k8s/scripts/health-check.sh --verbose

# Check ACME API
curl -s http://localhost:4001/directory | jq .
```

### Manual Deployment Steps

For step-by-step manual deployment, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Testing

This project includes comprehensive testing at multiple levels:

### Health Checks

Validate all services are running correctly:

```bash
# Basic health check
./k8s/scripts/health-check.sh

# Detailed health check with resource usage
./k8s/scripts/health-check.sh --verbose --resources
```

### Integration Tests

Run Boulder's complete integration test suite:

```bash
# Run integration tests
./k8s/scripts/run-integration-tests.sh

# Run with custom timeout
./k8s/scripts/run-integration-tests.sh --timeout 3600s
```

### Manual Testing

Test specific ACME functionality:

```bash
# Test ACME directory endpoint
curl -s http://localhost:4001/directory

# Test account creation (requires ACME client)
certbot register --server http://localhost:4001/acme/directory --email test@example.com
```

For comprehensive testing documentation, see [TESTING.md](TESTING.md).

## Configuration

### Service Configuration

Boulder services use JSON configuration files converted to Kubernetes ConfigMaps:

- **Service Discovery**: Consul SRV lookups replaced with Kubernetes DNS names
- **Database Access**: Connection strings stored in Secrets  
- **mTLS Certificates**: Internal PKI mounted as Secret volumes
- **WebPKI Certificates**: CA signing certificates mounted for certificate issuance

### Environment-Specific Configuration

The deployment supports different configuration profiles:

```bash
# Development (default)
kubectl apply -f k8s/

# Custom configuration
kubectl create configmap boulder-config --from-file=config/
```

### PKI Certificate Management

The deployment automatically manages two certificate hierarchies:

1. **WebPKI Hierarchy** - For certificate issuance operations
2. **Internal PKI** - For secure service-to-service communication

Certificates are generated using Boulder's existing certificate generation scripts and mounted as Kubernetes Secrets.

## Troubleshooting

### Common Issues

#### Cluster Connection Issues

```bash
# Verify kubectl configuration
kubectl config current-context
kubectl cluster-info

# For kind clusters
kind get kubeconfig --name boulder-k8s
```

#### Service Startup Issues

```bash
# Check pod status
kubectl get pods -n boulder

# View service logs
kubectl logs deployment/boulder-wfe2 -n boulder

# Check service dependencies
./k8s/scripts/health-check.sh --verbose
```

#### Database Connectivity

```bash
# Test database connection
kubectl exec -n boulder deployment/boulder-sa -- nc -zv proxysql 6033

# Check database logs
kubectl logs statefulset/mariadb -n boulder
```

For comprehensive troubleshooting guidance, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Getting Help

1. **Check Service Logs**: `kubectl logs <pod-name> -n boulder`
2. **Verify Health**: `./k8s/scripts/health-check.sh --verbose`
3. **Check Dependencies**: Ensure all prerequisite services are running
4. **Review Documentation**: See architecture docs for service interactions

## Contributing

### Development Workflow

1. **Follow Standards**: Implement according to [AGENTS.md](AGENTS.md) guidelines
2. **Test Thoroughly**: Ensure all integration tests pass
3. **Document Changes**: Update relevant documentation
4. **Lint Code**: Run `make lint` before submitting changes

### Code Quality

- All files must pass linting (`make lint`)
- Integration tests must pass (`./k8s/scripts/run-integration-tests.sh`)
- Documentation must be updated for any architectural changes
- Follow Kubernetes best practices for manifest structure

### Testing Requirements

```bash
# Run all quality checks
make lint

# Run all tests
make test

# Run specific test suites
make test-health
make test-integration
```

## License

This project follows Boulder's licensing. See the Boulder repository for license details.

---

**Project Status**: ✅ **Production Ready**

- All Boulder services implemented and tested
- Complete integration test suite passing
- Comprehensive documentation and troubleshooting guides
- Ready for development, testing, and production use cases

For detailed technical specifications, see [architecture/overview.md](architecture/overview.md).