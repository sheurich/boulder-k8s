# Boulder Kubernetes Implementation - Phase 1 Specification

> **Note:** This document is the authoritative source for all Boulder-specific technical specifications and implementation details.

## Objective

Containerize and deploy Let's Encrypt's Boulder services into a Kubernetes cluster to run its integration test suite in a pod-based microservice architecture.

## Architecture Decisions

### Service Discovery Strategy

- **Approach**: Kubernetes native load balancing with single Service per service type
- **Pattern**: Replace Consul SRV lookups with direct Kubernetes service DNS names
- **Example**: `boulder-sa` Service → multiple `boulder-sa` pods (Kubernetes handles load balancing)
- **Rationale**: Simpler than preserving Boulder's multi-instance service discovery

### Container Strategy

- **Base Image**: Use Boulder's existing `Containerfile` without modification
- **Deployment**: Single image with different command-line arguments per pod
- **Commands**: `boulder boulder-ca`, `boulder boulder-ra`, `boulder boulder-wfe2`, etc.
- **Rationale**: Leverages Boulder's existing containerization work

### Integration Testing

- **Scope**: Full Boulder integration test suite via `test/integration-test.py --chisel`
- **Execution**: Kubernetes Jobs running tests against deployed cluster services
- **Prerequisites**: Certificate generation via init containers (replaces `bsetup` service)

## Requirements

### Microservices as Pods

- Each Boulder mode (e.g., `sa`, `ra`, `va`, etc.) must be deployed as an independent Kubernetes pod.
- Use a single container image with different command-line arguments for each role.

### Service Discovery

- Replace Consul DNS with Kubernetes services for service-to-service communication.

#### Configuration Conversion Patterns

- Convert Boulder's JSON configs to Kubernetes ConfigMaps
- Use Secrets for sensitive data (database URLs, TLS keys, Redis passwords)
- Replace Consul SRV lookups with Kubernetes service DNS (e.g., `boulder-sa:9395`)
- Update `dnsAuthority` from `consul.service.consul` to cluster DNS

#### Service Discovery Pattern

Replace Consul patterns like:

```json
"srvLookup": {"service": "sa", "domain": "service.consul"}
```

With Kubernetes service names:

```json
"serverAddress": "boulder-sa:9395"
```

### Configuration Management

- Use Kubernetes ConfigMaps and Secrets to manage:
  - Database credentials
  - Redis connection strings
  - TLS certificates and keys
  - Boulder configuration files

### Supporting Services

- Include Redis and PostgreSQL as Kubernetes services.

### PKI and Certificate Management

- Use file-based PKCS#11 configuration (matching Boulder's test environment approach)
- Mount WebPKI certificates and keys as Kubernetes Secrets
- Configure Boulder CA services to use local certificate files via mounted volumes
- Generate test certificate hierarchies using Boulder's existing `test/certs/generate.sh` script
- Note: Network-based HSM integration with SoftHSM2 + pkcs11-proxy is planned for Phase 2

### Integration Testing

- Replicate Boulder's Python-based integration test scripts to run against the Kubernetes cluster.
- Ensure all inter-service dependencies (e.g., VA requires SA) are met at startup.

## Service Mapping & Dependencies

### Service Dependencies

Boulder services have strict startup dependencies that must be enforced using Kubernetes init containers:

**Infrastructure Layer** (start first):

- MariaDB (StatefulSet)
- ProxySQL (Deployment)
- Redis instances (2x StatefulSet for sharding)

**Foundation Services**:

- `remoteva-a/b/c` (no dependencies)
- `boulder-sa-1/2` (depends on ProxySQL → MariaDB)
- `boulder-publisher-1/2` (no dependencies)

**Validation Services**:

- `boulder-va-1/2` (depends on remoteva-a/b)

**Certificate Services**:

- `boulder-ra-sct-provider-1/2` (specialized RA instances for SCT operations, depends on publisher instances)
- `boulder-ca-1/2` (depends on SA + SCT providers)

**Registration Services**:

- `boulder-ra-1/2` (depends on SA + CA + VA + Publisher)

**Web Services**:

- `nonce-service-1/2` instances (depends on Redis)
- `boulder-wfe2` (depends on RA + SA + Nonce services)
- `sfe` (depends on RA + SA)

### Core Boulder Services (Essential for ACME Protocol)

> **Note:** The `boulder-ra-sct-provider` services are specialized instances of the Registration Authority (RA) that are required by Boulder's test environment for SCT (Signed Certificate Timestamp) operations.

| Service                       | Instances | Kubernetes Resources         | Dependencies                                                          | Commands                                                         |
| ----------------------------- | --------- | ---------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **boulder-sa-1**              | 1         | Deployment, Service          | MariaDB, ProxySQL                                                     | `boulder boulder-sa --config /etc/boulder/sa.json`               |
| **boulder-sa-2**              | 1         | Deployment, Service          | MariaDB, ProxySQL                                                     | `boulder boulder-sa --config /etc/boulder/sa.json`               |
| **boulder-ca-1**              | 1         | Deployment, Service          | boulder-sa-1/2                                                        | `boulder boulder-ca --config /etc/boulder/ca.json`               |
| **boulder-ca-2**              | 1         | Deployment, Service          | boulder-sa-1/2                                                        | `boulder boulder-ca --config /etc/boulder/ca.json`               |
| **boulder-ra-1**              | 1         | Deployment, Service          | boulder-sa-1/2, boulder-ca-1/2, boulder-va-1/2, boulder-publisher-1/2 | `boulder boulder-ra --config /etc/boulder/ra.json`               |
| **boulder-ra-2**              | 1         | Deployment, Service          | boulder-sa-1/2, boulder-ca-1/2, boulder-va-1/2, boulder-publisher-1/2 | `boulder boulder-ra --config /etc/boulder/ra.json`               |
| **boulder-va-1**              | 1         | Deployment, Service          | boulder-sa-1/2, remoteva-a/b/c                                        | `boulder boulder-va --config /etc/boulder/va.json`               |
| **boulder-va-2**              | 1         | Deployment, Service          | boulder-sa-1/2, remoteva-a/b/c                                        | `boulder boulder-va --config /etc/boulder/va.json`               |
| **boulder-wfe2**              | 1         | Deployment, Service, Ingress | boulder-ra-1/2, boulder-sa-1/2, nonce-service-1/2                     | `boulder boulder-wfe2 --config /etc/boulder/wfe2.json`           |
| **boulder-publisher-1**       | 1         | Deployment, Service          | -                                                                     | `boulder boulder-publisher --config /etc/boulder/publisher.json` |
| **boulder-publisher-2**       | 1         | Deployment, Service          | -                                                                     | `boulder boulder-publisher --config /etc/boulder/publisher.json` |
| **boulder-ra-sct-provider-1** | 1         | Deployment, Service          | boulder-publisher-1/2                                                 | `boulder boulder-ra --config /etc/boulder/ra-sct-provider.json`  |
| **boulder-ra-sct-provider-2** | 1         | Deployment, Service          | boulder-publisher-1/2                                                 | `boulder boulder-ra --config /etc/boulder/ra-sct-provider.json`  |
| **nonce-service-1**           | 1         | Deployment, Service          | Redis                                                                 | `boulder nonce-service --config /etc/boulder/nonce-service.json` |
| **nonce-service-2**           | 1         | Deployment, Service          | Redis                                                                 | `boulder nonce-service --config /etc/boulder/nonce-service.json` |
| **remoteva-a**                | 1         | Deployment, Service          | -                                                                     | `boulder remoteva --config /etc/boulder/remoteva-a.json`         |
| **remoteva-b**                | 1         | Deployment, Service          | -                                                                     | `boulder remoteva --config /etc/boulder/remoteva-b.json`         |
| **remoteva-c**                | 1         | Deployment, Service          | -                                                                     | `boulder remoteva --config /etc/boulder/remoteva-c.json`         |

### Supporting Services (Auxiliary Functionality)

| Service             | Kubernetes Resources | Dependencies                   | Commands                                                             |
| ------------------- | -------------------- | ------------------------------ | -------------------------------------------------------------------- |
| **sfe**             | Deployment, Service  | boulder-ra-1/2, boulder-sa-1/2 | `boulder sfe --config /etc/boulder/sfe.json`                         |
| **crl-storer**      | Deployment, Service  | boulder-sa-1/2                 | `boulder crl-storer --config /etc/boulder/crl-storer.json`           |
| **bad-key-revoker** | Deployment, Service  | boulder-sa-1/2                 | `boulder bad-key-revoker --config /etc/boulder/bad-key-revoker.json` |
| **log-validator**   | Deployment, Service  | boulder-sa-1/2                 | `boulder log-validator --config /etc/boulder/log-validator.json`     |
| **email-exporter**  | Deployment, Service  | boulder-sa-1/2                 | `boulder email-exporter --config /etc/boulder/email-exporter.json`   |

### Infrastructure Services (Data Layer)

| Service                 | Type        | Purpose                         |
| ----------------------- | ----------- | ------------------------------- |
| **MariaDB**             | StatefulSet | Primary database                |
| **ProxySQL**            | Deployment  | Database proxy/load balancer    |
| **Redis (2 instances)** | StatefulSet | Rate limiting and nonce storage |

## Configuration Conversion Requirements

When converting Boulder's Docker Compose configuration to Kubernetes:

1. **Service Discovery**: Replace all Consul SRV lookups with Kubernetes service DNS names
2. **Multi-Instance Services**: Use single Services with multiple pod endpoints instead of separate service instances
3. **Certificate Paths**: Update file paths to mount points from Secrets/ConfigMaps
4. **Database URLs**: Store in Secrets, reference via `dbConnectFile` pointing to mounted secret files
5. **Redis Configuration**: Convert Consul-based Redis discovery to direct Kubernetes service addresses

### Configuration Conversion Examples

#### Service Discovery Conversion

**Before (Consul SRV)**:

```json
{
  "saService": {
    "dnsAuthority": "consul.service.consul",
    "srvLookup": {
      "service": "sa",
      "domain": "service.consul"
    },
    "hostOverride": "sa.boulder"
  }
}
```

**After (Kubernetes DNS)**:

```json
{
  "saService": {
    "serverAddress": "boulder-sa:9395",
    "hostOverride": "sa.boulder"
  }
}
```

#### Multi-Instance Service Conversion

Boulder runs multiple instances of core services for load balancing. In Docker Compose, these are separate containers with different ports. In Kubernetes, we use a single Service with multiple pod endpoints.

**Example - Storage Authority**:

- Docker: `boulder-sa-1` (port 9395) + `boulder-sa-2` (port 9495)
- Kubernetes: Single `boulder-sa` Service with 2 pod endpoints, Kubernetes handles load balancing

## PKI Certificate Management

Boulder requires two distinct certificate hierarchies:

**WebPKI Hierarchy** (for CA operations):

- Generated using `test/certs/generate.sh`
- Must include root certs, intermediates, and PKCS#11 configs
- Mount as Secrets in CA service pods

**Internal PKI** (for mTLS between services):

- Internal CA certificate (`minica.pem`)
- Service-specific certificates (`sa.boulder`, `ra.boulder`, etc.)
- Mount in all Boulder service pods for gRPC authentication

### PKI Details

1. **WebPKI Hierarchy** (for certificate issuance):

   - Root certificates (RSA + ECDSA)
   - Intermediate certificates (multiple RSA + ECDSA)
   - PKCS#11 configuration files for each issuer

2. **Internal PKI** (for service mTLS):
   - Internal CA certificate (`minica.pem`)
   - Per-service certificates (`sa.boulder`, `ra.boulder`, `wfe.boulder`, etc.)

These must be generated using Boulder's `test/certs/generate.sh` script and packaged into Kubernetes Secrets.

## Testing Validation

- Verify service startup order and health checks via init containers
- Test ACME workflow end-to-end before considering deployment complete
- Ensure Boulder's integration tests pass using `test/integration-test.py --chisel`
- Validate load balancing across multiple service instances via metrics endpoints
- Confirm mTLS communication between all Boulder services

### Startup Dependencies

Use Kubernetes init containers to handle Boulder's strict service startup order:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: boulder-ra
spec:
  template:
    spec:
      initContainers:
        - name: wait-for-dependencies
          image: busybox
          command:
            [
              "sh",
              "-c",
              "until nslookup boulder-sa && nslookup boulder-ca && nslookup boulder-va; do sleep 2; done",
            ]
      containers:
        - name: boulder-ra
          image: boulder:latest
          command: ["/opt/boulder/bin/boulder"]
          args: ["boulder-ra", "--config", "/etc/boulder/ra.json"]
```

## Deployment Structure

Using a **component-based structure** following Kubernetes best practices with Boulder services logically grouped:

```
manifests/
├── namespace.yaml
├── infrastructure/
│   ├── redis/
│   │   ├── statefulset.yaml
│   │   └── service.yaml
│   ├── mariadb/
│   │   ├── statefulset.yaml
│   │   └── service.yaml
│   └── proxysql/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── boulder/
│   ├── sa/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── ca/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── ra/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── va/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── wfe2/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── ingress.yaml
│   ├── publisher/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── nonce-service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   ├── remoteva/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── sfe/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── shared/
│   ├── secrets.yaml
│   ├── rbac.yaml
│   └── network-policies.yaml
└── tests/
    └── integration-job.yaml
```

**Structure Benefits:**

- **Logical Grouping**: All Boulder services under `/boulder/` directory for clear organization
- **Component Isolation**: Each service directory contains all related resources (Deployment, Service, ConfigMap)
- **Standard Pattern**: Follows widely adopted microservice deployment patterns used by major Kubernetes projects
- **Maintainable**: Changes to a service affect only its directory, easy to find and modify resources
- **Phase 1 Focused**: Simple structure optimized for single-cluster deployment on `kind`

## Deliverables

- Kubernetes manifests (YAMLs) for all services and configurations following the structure above.
- Certificate generation Job to replace Boulder's `bsetup` service.
- Integration test Job that runs Boulder's full test suite against the cluster.
- Deployment script (`deploy.sh`) for one-command deployment on `kind`.
- Test script (`test.sh`) for running integration tests.
- Comprehensive README with deployment, testing, and troubleshooting instructions.
