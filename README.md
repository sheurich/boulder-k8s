# Boulder Kubernetes Project

A Kubernetes deployment for Boulder ACME Certificate Authority, converting Boulder from Docker Compose to a production-ready Kubernetes environment.

## Overview

[Boulder](https://github.com/letsencrypt/boulder) is the ACME Certificate Authority software that powers [Let's Encrypt](https://letsencrypt.org/), the world's largest certificate authority. Boulder implements the ACME protocol (RFC 8555) to provide automated certificate issuance and management for TLS certificates.

This project converts Boulder's traditional Docker Compose deployment to a scalable, production-ready Kubernetes deployment with proper service dependencies, health checks, and configuration management.

### Benefits of Kubernetes Deployment

- **Scalability**: Independent scaling of Boulder microservices based on load
- **High Availability**: Multi-instance deployments with proper load balancing
- **Resource Management**: Efficient resource allocation and limits per service
- **Health Monitoring**: Kubernetes-native health checks and service discovery
- **Configuration Management**: Centralized configuration via ConfigMaps and Secrets
- **Production Ready**: Support for HSM integration, monitoring, and CI/CD pipelines

## Documentation Structure

This project uses a phased approach with clear documentation hierarchy. Read documents in this order:

### Primary Documentation

1. **[`README.md`](README.md)** _(this file)_ - Project overview and getting started guide
2. **[`SPECp1.md`](SPECp1.md)** - **Complete technical specifications for Phase 1 deployment** _(authoritative source)_
3. **[`PROMPTp1.md`](PROMPTp1.md)** - Phase 1 implementation instructions for AI agents
4. **[`AGENTS.md`](AGENTS.md)** - General guidelines and standards for development agents

### Phase Specifications

- **[`SPECp1.md`](SPECp1.md)** - Phase 1: Basic Kubernetes deployment with core services
- **[`SPECp2.md`](SPECp2.md)** - Phase 2: Production enhancements (HSM, CI/CD, overlays)

**Note**: [`SPECp1.md`](SPECp1.md) is the authoritative technical specification document for Phase 1 implementation.

### Reference Materials

- **[`reference/BOULDER.md`](reference/BOULDER.md)** - Detailed Boulder architecture and technical guide
- **[`reference/boulder/`](reference/boulder/)** - Complete Boulder source code repository
- **[`reference/boulder.wiki/`](reference/boulder.wiki/)** - Boulder project wiki and documentation

## Quick Start Guide

### Prerequisites

Ensure you have the following tools installed:

- **Docker** - For container image management
- **Go** (1.21+) - For Boulder development and testing
- **Kubernetes cluster** - Local cluster using [`kind`](https://kind.sigs.k8s.io/) or production cluster
- **kubectl** - Kubernetes command-line tool

### Phase 1 Deployment

1. **Clone the repository**:

   ```bash
   git clone <repository-url>
   cd boulder-k8s
   ```

2. **Set up local Kubernetes cluster** (using kind):

   ```bash
   kind create cluster --name boulder
   ```

3. **Deploy Boulder to Kubernetes** (following [`SPECp1.md`](SPECp1.md)):

   ```bash
   # Deploy infrastructure services first
   kubectl apply -f manifests/infrastructure/

   # Deploy core Boulder services
   kubectl apply -f manifests/core-services/

   # Deploy supporting services
   kubectl apply -f manifests/supporting-services/
   ```

4. **Verify deployment**:

   ```bash
   # Check all pods are running
   kubectl get pods

   # Test ACME endpoint
   curl -k http://localhost:4001/directory
   ```

### Verification

Run Boulder's integration tests to verify the deployment:

```bash
# Run integration test job
kubectl apply -f manifests/tests/integration-job.yaml

# Check test results
kubectl logs job/boulder-integration-test
```

## Project Phases

### Phase 1: Basic Kubernetes Deployment

**Status**: _In Development_

Core functionality for running Boulder in Kubernetes as specified in [`SPECp1.md`](SPECp1.md):

#### ✅ **Completed Design Elements**

- Service dependency management with init containers
- Kubernetes-native service discovery (replacing Consul)
- ConfigMap and Secret management for configuration
- Multi-instance deployments for scalability
- Health checks and readiness probes
- Internal mTLS certificate management

#### 🔄 **Implementation Status**

- **Service Containerization**: Single Boulder image with different command-line arguments per service
- **Infrastructure Services**: MariaDB, ProxySQL, Redis (2 instances) deployment
- **Core Boulder Services**: SA, CA, RA, VA, WFE2, Publisher, Nonce Service, Remote VAs
- **Certificate Management**: PKI hierarchy generation and mounting as Secrets
- **Integration Testing**: Jobs running Boulder's test suite against cluster

#### **Key Deliverables** (per [`SPECp1.md`](SPECp1.md))

- Kubernetes manifests for all Boulder services
- Certificate generation Job (replacing `bsetup` service)
- Integration test Job running `test/integration-test.py --chisel`
- Deployment script (`deploy.sh`) for one-command deployment
- Test script (`test.sh`) for running integration tests

### Phase 2: Production Enhancements

**Status**: _Planned_ (detailed in [`SPECp2.md`](SPECp2.md))

Production-ready features and operational capabilities:

- 🔄 **HSM Integration**: Network-based Hardware Security Module support with SoftHSM2 + pkcs11-proxy
- 🔄 **Multi-Environment Support**: Kustomize overlays for dev/staging/prod environments
- 🔄 **CI/CD Integration**: GitHub Actions workflows for automated testing and deployment
- 🔄 **Monitoring Stack**: Prometheus monitoring and Grafana dashboards
- 🔄 **Secrets Management**: Integration with cloud-native secret management
- 🔄 **Advanced Networking**: Security policies and production networking configuration

## Architecture Overview

Boulder follows a microservices architecture with strict service dependencies as detailed in [`SPECp1.md`](SPECp1.md):

### Core Boulder Services

| Service                         | Purpose                                 | Dependencies          |
| ------------------------------- | --------------------------------------- | --------------------- |
| **Web Frontend (WFE2)**         | Public ACME API endpoint                | RA, SA, Nonce Service |
| **Registration Authority (RA)** | Certificate request processing          | SA, CA, VA, Publisher |
| **Certificate Authority (CA)**  | Certificate signing and issuance        | SA, RA (SCT Provider) |
| **Storage Authority (SA)**      | Database operations and persistence     | MariaDB, ProxySQL     |
| **Validation Authority (VA)**   | Domain ownership verification           | SA, Remote VAs        |
| **Publisher**                   | Certificate Transparency log submission | _(none)_              |
| **Nonce Service**               | Anti-replay nonce generation            | Redis                 |
| **Remote VAs (a/b/c)**          | Multi-perspective validation            | _(none)_              |

### Infrastructure Services

| Service                 | Type        | Purpose                         |
| ----------------------- | ----------- | ------------------------------- |
| **MariaDB**             | StatefulSet | Primary database                |
| **ProxySQL**            | Deployment  | Database proxy/load balancer    |
| **Redis (2 instances)** | StatefulSet | Rate limiting and nonce storage |

### Service Dependencies Flow

Boulder services must start in specific order due to dependencies (enforced via init containers):

```
Infrastructure → Foundation → Validation → Certificate → Registration → Web
     ↓               ↓           ↓            ↓             ↓          ↓
  MariaDB      →    SA       →    VA    →     CA       →    RA    →  WFE2
  ProxySQL          Publisher      ↑                       ↑        ↑
  Redis      →   Remote VAs   ────┘                       │        │
                                                          │        └→ SFE
                                                          └→ Nonce Service
```

### Container Strategy

- **Single Image**: Boulder's existing `Containerfile` provides one image for all services
- **Service Differentiation**: Different command-line arguments per pod (`boulder boulder-ca`, `boulder boulder-ra`, etc.)
- **Configuration**: JSON configs converted to Kubernetes ConfigMaps and Secrets

## Development Workflow

### Implementation Process

1. **Read Specifications**: Start with [`SPECp1.md`](SPECp1.md) for complete technical requirements
2. **Follow Agent Guidelines**: Adhere to standards in [`AGENTS.md`](AGENTS.md)
3. **Reference Architecture**: Use [`reference/BOULDER.md`](reference/BOULDER.md) for Boulder technical details
4. **Test Integration**: Verify Boulder's integration tests pass after modifications

### Key Conventions

#### Kubernetes Resources (from [`AGENTS.md`](AGENTS.md))

- **Naming**: Use kebab-case for resource names (e.g., `boulder-sa`, `boulder-wfe2`)
- **File Organization**: Group related manifests logically in separate files
- **Dependencies**: Use init containers to enforce service startup order

#### Configuration Management

- **Service Discovery**: Convert Consul SRV lookups to Kubernetes service DNS names
- **Secrets**: Store sensitive data (database URLs, TLS keys) in Kubernetes Secrets
- **ConfigMaps**: Store Boulder JSON configuration files as ConfigMaps
- **Multi-Instance**: Use single Services with multiple pod endpoints for load balancing

### File Structure (per [`SPECp1.md`](SPECp1.md))

```
boulder-k8s/
├── README.md                    # Project overview (this file)
├── SPECp1.md                   # Phase 1 technical specifications ⭐
├── PROMPTp1.md                 # Phase 1 implementation guide
├── AGENTS.md                   # Development standards and guidelines
├── manifests/                  # Kubernetes manifests
│   ├── namespace.yaml
│   ├── infrastructure/         # MariaDB, Redis, ProxySQL
│   │   ├── mariadb.yaml
│   │   ├── proxysql.yaml
│   │   └── redis.yaml
│   ├── core-services/          # Essential Boulder services
│   │   ├── boulder-sa.yaml
│   │   ├── boulder-ca.yaml
│   │   ├── boulder-ra.yaml
│   │   ├── boulder-va.yaml
│   │   ├── boulder-wfe2.yaml
│   │   ├── boulder-publisher.yaml
│   │   └── remoteva.yaml
│   ├── supporting-services/    # Auxiliary services
│   │   ├── nonce-service.yaml
│   │   └── sfe.yaml
│   ├── config/                 # Configuration management
│   │   ├── boulder-configs.yaml    # ConfigMaps
│   │   └── boulder-secrets.yaml    # Secrets
│   └── tests/                  # Integration testing
│       └── integration-job.yaml
├── deploy.sh                   # One-command deployment script
├── test.sh                     # Integration test script
└── reference/                  # Boulder documentation and source
    ├── BOULDER.md             # Technical architecture guide
    ├── boulder/               # Boulder source code
    └── boulder.wiki/          # Additional documentation
```

## Configuration Management

### Service Discovery Conversion

Boulder services are converted from Consul-based service discovery to Kubernetes DNS:

**Before (Consul SRV)**:

```json
{
  "saService": {
    "dnsAuthority": "consul.service.consul",
    "srvLookup": {
      "service": "sa",
      "domain": "service.consul"
    }
  }
}
```

**After (Kubernetes DNS)**:

```json
{
  "saService": {
    "serverAddress": "boulder-sa:9395"
  }
}
```

### PKI Certificate Management

Boulder requires two distinct certificate hierarchies (detailed in [`SPECp1.md`](SPECp1.md)):

#### 1. WebPKI Hierarchy (for CA operations)

- **Generation**: Using Boulder's `test/certs/generate.sh` script
- **Components**: Root certificates, intermediate certificates, PKCS#11 configs
- **Storage**: Kubernetes Secrets mounted in CA service pods
- **Key Types**: RSA and ECDSA certificate chains

#### 2. Internal PKI (for service mTLS)

- **Purpose**: Secure gRPC communication between Boulder services
- **Components**: Internal CA certificate (`minica.pem`), per-service certificates
- **Storage**: Kubernetes Secrets mounted in all Boulder service pods
- **Certificates**: `sa.boulder`, `ra.boulder`, `ca.boulder`, `wfe.boulder`, etc.

### Database Configuration

- **Connection Management**: Database URLs stored in Secrets, referenced via `dbConnectFile`
- **Load Balancing**: ProxySQL provides connection pooling between SA services and MariaDB
- **Schema Management**: Database migrations handled by SA service during startup

## Testing and Validation

### Integration Testing

Boulder's comprehensive test suite validates the Kubernetes deployment:

```bash
# Integration test using Boulder's existing test framework
./test/integration-test.py --chisel

# Test specific ACME workflows
./test/integration-test.py --chisel --filter test_http_challenge
```

### Service Validation Checklist

- ✅ **Service Startup Order**: Init containers enforce proper dependencies
- ✅ **Health Checks**: All pods pass readiness and liveness probes
- ✅ **Load Balancing**: Traffic distributed across service replicas
- ✅ **mTLS Communication**: Secure gRPC communication between services
- ✅ **ACME Functionality**: End-to-end certificate issuance workflow
- ✅ **Multi-Perspective Validation**: Remote VAs providing distributed validation

### Required Test Results

- All Boulder integration tests pass (`test/integration-test.py --chisel`)
- ACME directory endpoint responds correctly
- Certificate issuance workflow completes successfully
- Challenge validation works for HTTP-01, DNS-01, TLS-ALPN-01
- Service health endpoints report healthy status

## Tools and Resources

### Development Environment

- **macOS Host**: Docker, Go, and Kubernetes (`kind`) pre-installed
- **Boulder Repository**: Complete source code and integration test scripts
- **MCP Tools**: context7, github, and rfc-server for enhanced development support

### External Resources

- [Boulder GitHub Repository](https://github.com/letsencrypt/boulder) - Official Boulder source
- [ACME Specification (RFC 8555)](https://tools.ietf.org/html/rfc8555) - ACME protocol standard
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/) - CA operational documentation
- [Kubernetes Documentation](https://kubernetes.io/docs/) - Container orchestration reference

## Current Status and Roadmap

### Implementation Status

#### **Phase 1**: _In Active Development_

- **Specifications**: Complete (see [`SPECp1.md`](SPECp1.md))
- **Architecture Design**: ✅ Complete - Service dependencies and conversion patterns defined
- **Configuration Conversion**: ✅ Specified - Consul to Kubernetes DNS patterns documented
- **Kubernetes Manifests**: 🔄 _In Progress_ - Core service deployments being implemented
- **PKI Management**: ✅ Specified - Certificate generation and mounting strategy defined
- **Integration Testing**: ✅ Framework Ready - Test job specifications complete

#### **Implementation Priorities**

1. **Infrastructure Services** - MariaDB, ProxySQL, Redis deployments
2. **Foundation Services** - SA, Publisher, Remote VA deployments
3. **Core Services** - CA, RA, VA deployments with proper init container dependencies
4. **Web Services** - WFE2, SFE, Nonce Service deployments
5. **Configuration Management** - ConfigMap and Secret generation from Boulder configs
6. **Integration Testing** - Boulder test suite execution in Kubernetes Jobs

### Next Steps

#### **Complete Phase 1 Implementation**

1. **Finish Kubernetes Manifests** - Complete all service deployments per [`SPECp1.md`](SPECp1.md)
2. **Certificate Generation Job** - Implement replacement for Boulder's `bsetup` service
3. **Configuration Conversion** - Convert all Boulder JSON configs to ConfigMaps/Secrets
4. **Integration Testing** - Validate end-to-end ACME functionality with `test/integration-test.py --chisel`
5. **Deployment Automation** - Complete `deploy.sh` and `test.sh` scripts

#### **Phase 2 Planning** (per [`SPECp2.md`](SPECp2.md))

1. **HSM Integration Architecture** - Network-based SoftHSM2 + pkcs11-proxy design
2. **Multi-Environment Support** - Kustomize overlays for dev/staging/prod
3. **CI/CD Pipeline Integration** - GitHub Actions workflows for automated testing
4. **Monitoring and Observability** - Prometheus + Grafana stack integration

### Contributing

This project follows Boulder's development standards and Kubernetes best practices:

#### **Implementation Guidelines**

- **Compatibility**: Maintain full compatibility with Boulder's ACME protocol implementation
- **Security**: Ensure all changes maintain or improve security posture
- **Testing**: Validate all changes using Boulder's comprehensive integration test suite
- **Documentation**: Keep [`SPECp1.md`](SPECp1.md) as the authoritative technical specification

#### **Development Process**

1. **Read Specifications**: Review [`SPECp1.md`](SPECp1.md) for technical requirements
2. **Follow Standards**: Implement according to [`AGENTS.md`](AGENTS.md) guidelines
3. **Test Thoroughly**: Ensure `test/integration-test.py --chisel` passes
4. **Document Changes**: Update relevant documentation for any architectural modifications

---

**Project Goal**: Transform Boulder ACME CA into a scalable, production-ready Kubernetes deployment while maintaining full compatibility with the ACME protocol and Let's Encrypt's operational requirements.

For detailed implementation specifications, see **[`SPECp1.md`](SPECp1.md)**.
