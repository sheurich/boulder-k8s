# Boulder Kubernetes Implementation - Phase 1 Specification

> **Navigation:** See [`README.md`](../README.md) for project overview | **This is Phase 1** | See `SPECp2.md` for the next phase

> **Note:** This document is the authoritative source for all Boulder-specific technical specifications and implementation details for Phase 1.

## 1. Objective & Guiding Principle

The primary objective of Phase 1 is to create a high-fidelity replica of the standard Boulder `docker-compose` development environment within Kubernetes.

**Guiding Principle:** The deployment should be functionally equivalent to running `docker-compose up` in the upstream Boulder repository. The ultimate measure of success is the ability to run Boulder's full integration test suite (`test/integration-test.py --chisel`) against this new Kubernetes-based deployment and have it pass. This ensures we have a complete, functional, and validated ACME CA before moving on to production-hardening in Phase 2.

> **Upstream Reference:** For a comprehensive overview of the upstream Boulder development environment, including its architecture, service dependencies, and configuration, please consult the [Boulder Development Environment Guide](reference/BOULDER.md). This guide is an essential resource for understanding the patterns this Kubernetes implementation adapts.

## 2. Architecture

This section outlines the core architectural decisions for the Kubernetes deployment.

### 2.1. Containerization
- **Base Image**: Use Boulder's existing `Containerfile` without modification.
- **Deployment**: A single container image will be used for all Boulder services, with the specific service role (e.g., `boulder-ca`, `boulder-ra`) determined by command-line arguments.

### 2.2. Service Discovery
- **Approach**: Kubernetes-native service discovery will replace Consul.
- **Pattern**: Services will communicate directly using Kubernetes service DNS names (e.g., `boulder-sa.boulder.svc.cluster.local`). Boulder's `srvLookup` configurations will be replaced with static `serverAddress` entries.
- **Load Balancing**: A single Kubernetes Service will load-balance traffic across multiple pods for a given Boulder service type (e.g., a `boulder-sa` Service fronts two `boulder-sa` pods).

### 2.3. Configuration Management
- **Configuration**: Boulder's JSON configuration files will be stored in Kubernetes ConfigMaps.
- **Secrets**: Sensitive data (database credentials, TLS keys, API keys) will be stored in Kubernetes Secrets.
- **Database URL**: Database connection strings will be stored in Secrets and mounted as files, referenced via Boulder's `dbConnectFile` setting.

### 2.4. PKI & Security
- **mTLS**: All inter-service gRPC communication must be secured with mutual TLS (mTLS). This is a core requirement for Boulder's gRPC services and cannot be disabled.
- **Internal PKI**: An internal Certificate Authority (CA) will be used to issue certificates for mTLS. `cert-manager` is used for automating the lifecycle of these internal certificates.
- **WebPKI**: The WebPKI certificate hierarchy required for CA operations will be generated using Boulder's `test/certs/generate.sh` script and mounted into CA pods as Kubernetes Secrets.
- **HSM**: A SoftHSM sidecar pattern with PKCS#11 proxy provides certificate signing capabilities, matching Boulder's test environment requirements for Phase 1. This enables complete certificate signing functionality for integration testing.

### 2.5. Integration Testing
- **Execution**: The full Boulder integration test suite (`test/integration-test.py --chisel`) will be run as a Kubernetes Job.
- **Prerequisites**: Certificate generation, previously handled by `bsetup`, will be performed by an init container or a dedicated Kubernetes Job.

## 3. Service Definitions

Each Boulder service will be deployed as a Kubernetes Deployment, exposed via a Service.

### 3.1. Service Dependencies and Startup Order

Boulder services have strict startup dependencies that must be enforced. Kubernetes init containers should be used to wait for dependencies to become available before starting a service pod.

> **Scope Note:** The Phase 1 deployment must include all Boulder services required to pass the integration test suite. This includes not only the core services but also supporting components like `boulder-publisher`, `nonce-service`, and the `remoteva` instances, mirroring the upstream `docker-compose` environment.

**Startup Order:**
1.  **Infrastructure Layer**: MariaDB, ProxySQL, Redis.
2.  **Foundation Services**: `boulder-sa`, `boulder-publisher`, `remoteva`.
3.  **Core Services**: `boulder-va`, `boulder-ca`, `boulder-ra`, `nonce-service`.
4.  **Web & Edge Services**: `boulder-wfe2`, `sfe`.

**Example Init Container:**
An `initContainer` can poll for the DNS resolution of its dependencies.
```yaml
# Example for boulder-ra, which depends on sa, ca, and va
initContainers:
- name: wait-for-dependencies
  image: busybox:1.36
  command: ['sh', '-c', 'until nslookup boulder-sa && nslookup boulder-ca && nslookup boulder-va; do echo "waiting for dependencies..."; sleep 2; done']
```

### 3.2. Service-to-Resource Mapping

The following tables map Boulder services to Kubernetes resources and their dependencies.

#### Core Boulder Services
| Service | Replicas | Dependencies |
|---|---|---|
| **boulder-sa** | 2 | MariaDB/ProxySQL |
| **boulder-ca** | 2 | `boulder-sa` |
| **boulder-ra** | 2 | `boulder-sa`, `boulder-ca`, `boulder-va`, `boulder-publisher` |
| **boulder-va** | 2 | `boulder-sa`, `remoteva` |
| **boulder-wfe2** | 1 | `boulder-ra`, `boulder-sa`, `nonce-service` |
| **boulder-publisher** | 2 | - |
| **boulder-ra-sct-provider** | 2 | `boulder-publisher` |
| **nonce-service** | 2 | Redis |
| **remoteva** | 3 | - |

> **OCSP Exclusion:** This implementation intentionally excludes all OCSP-related functionality and services, as they are deprecated in the core Boulder software.
> 
> **Note:** The `boulder-ra-sct-provider` is a specialized instance of the RA.

### 3.3. Multi-Perspective Issuance Corroboration (MPIC)

To enhance security against network-level attacks like BGP hijacking, Boulder employs Multi-Perspective Issuance Corroboration (MPIC). This requires that domain control validation be performed from multiple network vantage points.

**Implementation Requirements:**
- The primary `boulder-va` service orchestrates the validation.
- Three distinct `remoteva` deployments (`remoteva-a`, `remoteva-b`, `remoteva-c`) must be deployed. Each must be configured with a unique `perspective` and `rir` (Regional Internet Registry) to ensure network diversity.
- **Quorum Rule**: For a validation challenge to succeed, the primary `boulder-va` check must pass, and **at least 2 of the 3** `remoteva` instances must also return a successful validation.
- **RIR Diversity**: The set of successful `remoteva` instances must represent at least **2 different RIRs**.

These requirements must be reflected in the `va.json` configuration file, which lists the gRPC addresses and expected perspectives of the `remoteva` services.

#### Supporting Services
| Service | Replicas | Dependencies |
|---|---|---|
| **sfe** | 1 | `boulder-ra`, `boulder-sa` |
| **crl-storer** | 1 | `boulder-sa` |
| **bad-key-revoker** | 1 | `boulder-sa` |
| **log-validator** | 1 | `boulder-sa` |
| **email-exporter** | 1 | `boulder-sa` |

#### Infrastructure Services
| Service | Kubernetes Resource | Purpose |
|---|---|---|
| **MariaDB** | StatefulSet | Primary database |
| **ProxySQL** | Deployment | Database proxy/load balancer |
| **Redis** | StatefulSet (x2) | Rate limiting and nonce storage |

## 4. Configuration Conversion Patterns

This section provides examples of how Boulder's original configuration should be adapted for Kubernetes.

### 4.1. Service Discovery (Consul to Kubernetes)

Replace Consul SRV lookups with direct Kubernetes service DNS names.

**Before (Consul SRV in `ra.json`)**:
```json
{
  "saService": {
    "dnsAuthority": "consul.service.consul",
    "srvLookup": { "service": "sa", "domain": "service.consul" },
    "hostOverride": "sa.boulder"
  }
}
```

**After (Kubernetes DNS in `ra.json`)**:
```json
{
  "saService": {
    "serverAddress": "boulder-sa:9395",
    "hostOverride": "sa.boulder"
  }
}
```

### 4.2. mTLS Configuration

Client and server certificate paths must be configured for mTLS.

**Example (`ra.json` connecting to `sa.boulder`)**:
```json
{
  "saService": {
    "serverAddress": "boulder-sa:9395",
    "hostOverride": "sa.boulder",
    "clientCertificate": "/etc/boulder/certs/ra.boulder.crt",
    "clientKey": "/etc/boulder/certs/ra.boulder.key",
    "serverCertificate": "/etc/boulder/certs/minica.pem"
  }
}
```

### 4.3. DNS Resolver Configuration

The Validation Authority (VA) must be configured to use external DNS resolvers for challenge validation, preferably via DNS-over-HTTPS (DoH).

**Example (`va.json`)**:
```json
{
  "dnsResolver": "https://cloudflare-dns.com/dns-query",
  "dnsTries": 3
}
```

## 5. Infrastructure and Database

### 5.1. Database Initialization
A Kubernetes Job must be used to initialize the database schema before the `boulder-sa` service starts. The schema migration scripts are available in the Boulder source code.

### 5.2. DNS
The cluster must have a functional DNS service (e.g., CoreDNS). Network policies should be configured to allow Boulder services to make external DNS queries for challenge validation.

## 6. Testing and Validation

The deployment is considered complete only after the following criteria are met:
- All service pods are running and healthy.
- Startup dependencies are correctly handled by init containers.
- The Boulder integration test suite (`test/integration-test.py --chisel`) passes when run as a Kubernetes Job.
- The database initialization job completes successfully.
- Load balancing across multiple service instances is confirmed.

## 7. Deployment Structure

A component-based directory structure will be used for all Kubernetes manifests.

```text
k8s/
├── namespaces/
│   └── boulder-namespace.yaml
├── deployments/
│   ├── infrastructure/
│   │   ├── mariadb.yaml
│   │   ├── redis.yaml
│   │   └── proxysql.yaml
│   └── boulder/
│       ├── ca.yaml
│       ├── sa.yaml
│       ├── ra.yaml
│       ├── va.yaml
│       ├── wfe2.yaml
│       ├── publisher.yaml
│       ├── nonce-service.yaml
│       └── remote-va1.yaml
├── services/
│   ├── infrastructure/
│   └── boulder/
├── secrets/
│   └── db-credentials.yaml
├── jobs/
│   ├── db-init.yaml
│   └── boulder-integration-test.yaml
└── scripts/
    ├── deploy.sh
    ├── health-check.sh
    └── run-integration-tests.sh
```
> **Note:** Each component directory (e.g., `boulder/sa/`) should contain its respective Deployment, Service, and ConfigMap manifests.

## 8. Deliverables

- All Kubernetes manifests (YAMLs) organized according to the deployment structure.
- `cert-manager` deployment manifests.
- Database initialization Job.
- Scripts or Job to generate and load PKI certificates into Secrets.
- Integration test Job definition.
- A `Makefile` with `deploy` and `test` targets that orchestrate deployment and testing to a local `kind` cluster.
- Comprehensive `README.md` with deployment, testing, and troubleshooting instructions.
