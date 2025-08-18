# Boulder Kubernetes Implementation - Phase 1 Specification

> **Note:** This document is the authoritative source for all Boulder-specific technical specifications and implementation details for Phase 1.

## 1. Objective

Containerize and deploy Let's Encrypt's Boulder services into a Kubernetes cluster to run its integration test suite in a pod-based microservice architecture.

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
- **mTLS**: All inter-service gRPC communication must be secured with mutual TLS (mTLS).
- **Internal PKI**: An internal Certificate Authority (CA) will be used to issue certificates for mTLS. `cert-manager` is recommended for automating the lifecycle of these internal certificates.
- **WebPKI**: The WebPKI certificate hierarchy required for CA operations will be generated using Boulder's `test/certs/generate.sh` script and mounted into CA pods as Kubernetes Secrets.
- **HSM**: A file-based PKCS#11 configuration will be used, matching Boulder's test environment. Network HSM integration is deferred to Phase 2.

### 2.5. Integration Testing
- **Execution**: The full Boulder integration test suite (`test/integration-test.py --chisel`) will be run as a Kubernetes Job.
- **Prerequisites**: Certificate generation, previously handled by `bsetup`, will be performed by an init container or a dedicated Kubernetes Job.

## 3. Service Definitions

Each Boulder service will be deployed as a Kubernetes Deployment, exposed via a Service.

### 3.1. Service Dependencies and Startup Order

Boulder services have strict startup dependencies that must be enforced. Kubernetes init containers should be used to wait for dependencies to become available before starting a service pod.

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

> **Note:** The `remoteva` service will have three distinct deployments (`remoteva-a`, `remoteva-b`, `remoteva-c`) each with its own configuration, but they can be addressed collectively if needed. The `boulder-ra-sct-provider` is a specialized instance of the RA.

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
- mTLS is enforced for all service-to-service communication.
- `cert-manager` successfully provisions and renews internal certificates.
- The database initialization job completes successfully.
- Load balancing across multiple service instances is confirmed.

## 7. Deployment Structure

A component-based directory structure will be used for all Kubernetes manifests.

```text
manifests/
├── namespace.yaml
├── infrastructure/
│   ├── cert-manager/
│   ├── redis/
│   ├── mariadb/
│   └── proxysql/
├── boulder/
│   ├── sa/
│   ├── ca/
│   ├── ra/
│   ├── va/
│   ├── wfe2/
│   ├── publisher/
│   ├── nonce-service/
│   └── remoteva/
├── security/
│   ├── pki/
│   └── network-policies/
├── data/
│   └── database-init-job.yaml
├── shared/
│   ├── secrets.yaml
│   └── rbac.yaml
└── tests/
    └── integration-test-job.yaml
```
> **Note:** Each component directory (e.g., `boulder/sa/`) should contain its respective Deployment, Service, and ConfigMap manifests.

## 8. Deliverables

- All Kubernetes manifests (YAMLs) organized according to the deployment structure.
- `cert-manager` deployment manifests.
- Database initialization Job.
- Scripts or Job to generate and load PKI certificates into Secrets.
- Integration test Job definition.
- A `deploy.sh` script for one-command deployment to a local `kind` cluster.
- A `test.sh` script to execute the integration test Job.
- Comprehensive `README.md` with deployment, testing, and troubleshooting instructions.
