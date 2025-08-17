# Phase 1 Spec: Kubernetes-Based Boulder Integration Environment

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

### Core Boulder Services (Essential for ACME Protocol)

| Service               | Kubernetes Resources         | Dependencies                                          | Commands                                                         |
| --------------------- | ---------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------- |
| **boulder-sa**        | Deployment, Service          | MariaDB, ProxySQL                                     | `boulder boulder-sa --config /etc/boulder/sa.json`               |
| **boulder-ca**        | Deployment, Service          | boulder-sa                                            | `boulder boulder-ca --config /etc/boulder/ca.json`               |
| **boulder-ra**        | Deployment, Service          | boulder-sa, boulder-ca, boulder-va, boulder-publisher | `boulder boulder-ra --config /etc/boulder/ra.json`               |
| **boulder-va**        | Deployment, Service          | boulder-sa, remoteva-\*                               | `boulder boulder-va --config /etc/boulder/va.json`               |
| **boulder-wfe2**      | Deployment, Service, Ingress | boulder-ra, boulder-sa, nonce-service                 | `boulder boulder-wfe2 --config /etc/boulder/wfe2.json`           |
| **boulder-publisher** | Deployment, Service          | -                                                     | `boulder boulder-publisher --config /etc/boulder/publisher.json` |
| **nonce-service**     | Deployment, Service          | Redis                                                 | `boulder nonce-service --config /etc/boulder/nonce-service.json` |
| **remoteva-a/b/c**    | Deployment, Service          | -                                                     | `boulder remoteva --config /etc/boulder/remoteva-a.json`         |

### Supporting Services (Auxiliary Functionality)

| Service | Kubernetes Resources | Dependencies           | Commands                                     |
| ------- | -------------------- | ---------------------- | -------------------------------------------- |
| **sfe** | Deployment, Service  | boulder-ra, boulder-sa | `boulder sfe --config /etc/boulder/sfe.json` |

### Infrastructure Services (Data Layer)

| Service                 | Type        | Purpose                         |
| ----------------------- | ----------- | ------------------------------- |
| **MariaDB**             | StatefulSet | Primary database                |
| **ProxySQL**            | Deployment  | Database proxy/load balancer    |
| **Redis (2 instances)** | StatefulSet | Rate limiting and nonce storage |

## Configuration Conversion Examples

### Service Discovery Conversion

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

```
manifests/
├── namespace.yaml
├── infrastructure/
│   ├── redis.yaml
│   ├── mariadb.yaml
│   └── proxysql.yaml
├── core-services/
│   ├── boulder-sa.yaml
│   ├── boulder-ca.yaml
│   ├── boulder-ra.yaml
│   ├── boulder-va.yaml
│   ├── boulder-wfe2.yaml
│   ├── boulder-publisher.yaml
│   └── remoteva.yaml
├── supporting-services/
│   ├── nonce-service.yaml
│   └── sfe.yaml
├── config/
│   ├── boulder-configs.yaml (ConfigMaps)
│   └── boulder-secrets.yaml (Secrets)
└── tests/
    └── integration-job.yaml
```

## Deliverables

- Kubernetes manifests (YAMLs) for all services and configurations following the structure above.
- Certificate generation Job to replace Boulder's `bsetup` service.
- Integration test Job that runs Boulder's full test suite against the cluster.
- Deployment script (`deploy.sh`) for one-command deployment on `kind`.
- Test script (`test.sh`) for running integration tests.
- Comprehensive README with deployment, testing, and troubleshooting instructions.
