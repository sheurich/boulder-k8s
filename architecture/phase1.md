# Boulder Kubernetes Architecture - Phase 1

> **Authority:** This document supports [`reference/SPECp1.md`](../reference/SPECp1.md), which is the authoritative specification for Phase 1 requirements.

## Overview

Phase 1 creates a high-fidelity replica of Boulder's `docker-compose` development environment within Kubernetes. The deployment provides functional equivalence to running `docker-compose up` in the upstream Boulder repository and must pass Boulder's full integration test suite (`test/integration-test.py --chisel`).

### Design Principles

1. **Development Environment Fidelity**: Replicates Boulder's test environment behavior exactly
2. **Service Discovery**: Kubernetes Services replace Consul SRV lookups
3. **Dependency Management**: Init containers enforce proper startup order
4. **Security Foundation**: mTLS for all gRPC communication, HSM for certificate signing
5. **Testing Focus**: Enables complete Boulder integration test suite execution

---

## Service Architecture

### Boulder Microservices Overview

Boulder implements ACME through distributed microservices with clear separation of concerns:

#### Core ACME Services

| Service | Purpose | Instances | gRPC Ports | Debug Ports |
|---------|---------|-----------|------------|-------------|
| **Web Front End (WFE2)** | Public ACME API endpoint | 1 | N/A | 8013 |
| **Registration Authority (RA)** | Certificate issuance workflow orchestration | 2 | 9394/9494 | 8002/8102 |
| **Certificate Authority (CA)** | Certificate signing and CRL generation | 2 | 9393/9493 | 8001/8101 |
| **Storage Authority (SA)** | Database abstraction layer | 2 | 9395/9495 | 8003/8103 |
| **Validation Authority (VA)** | Domain control validation | 2 | 9392/9492 | 8004/8104 |

#### Supporting Services

| Service | Purpose | Instances | gRPC Ports | Debug Ports |
|---------|---------|-----------|------------|-------------|
| **Publisher** | Certificate Transparency compliance | 2 | 9391/9491 | 8009/8109 |
| **SCT Provider** | Specialized RA for SCT operations | 2 | 9594/9694 | 8118/8119 |
| **Nonce Service** | Replay attack prevention | 3 | 9301/9501/9401 | 8111/8113/8112 |
| **Remote VAs** | Multi-perspective validation (MPIC) | 3 | 9397/9498/9499 | 8011/8012/8023 |

#### Administrative Services

| Service | Purpose | Instances | gRPC Ports | Debug Ports |
|---------|---------|-----------|------------|-------------|
| **Self-service Front End (SFE)** | Account management portal | 1 | N/A | 8015 |
| **CRL Storer** | CRL management and distribution | 2 | 9503/9603 | 8024/8124 |
| **Bad Key Revoker** | Security monitoring | 1 | 9504 | 8025 |
| **Log Validator** | CT log monitoring | 1 | 9505 | 8026 |
| **Email Exporter** | Email metrics and notifications | 1 | 9506 | 8027 |

**Authority:** For complete service specifications, see [`architecture/shared/service-matrix.md`](shared/service-matrix.md).

---

## Service Dependencies

### Startup Order

Services must start in strict dependency order, enforced by Kubernetes init containers:

1. **Infrastructure** (Parallel): MariaDB, Redis, ProxySQL
2. **Foundation** (Parallel): boulder-sa, boulder-publisher, remoteva services
3. **Validation**: boulder-va (after remoteva services)
4. **Certificate**: boulder-ra-sct-provider (after publisher), boulder-ca (after SA + SCT)
5. **Registration**: boulder-ra (after CA, VA, SA, publisher)
6. **Web**: nonce-service (after Redis), boulder-wfe2 (after RA, SA, nonce)
7. **Support**: All administrative services (after SA)

### Multi-Perspective Validation (MPIC)

Boulder implements MPIC security through distributed validation:

- **Primary VA**: Orchestrates validation challenges
- **Remote VAs**: Three instances (`remoteva-a`, `remoteva-b`, `remoteva-c`) with unique perspectives
- **Quorum Rule**: Primary VA check + at least 2 of 3 remote VAs must succeed
- **RIR Diversity**: Successful remote VAs must represent at least 2 different Regional Internet Registries

---

## Kubernetes Deployment Architecture

### Resource Mapping

| Boulder Service | Kubernetes Resource | Configuration |
|----------------|-------------------|---------------|
| Boulder Services | Deployment (2+ replicas) | Multi-instance services |
| Infrastructure | StatefulSet | Persistent storage |
| Service Discovery | Service (ClusterIP) | Load balancing |
| Configuration | ConfigMap | JSON configs |
| Secrets | Secret | Credentials, certificates |

### Configuration Management

#### Service Discovery Pattern

**Original Docker Compose (Consul):**
```json
{
  "saService": {
    "dnsAuthority": "consul.service.consul",
    "srvLookup": { "service": "sa", "domain": "service.consul" }
  }
}
```

**Kubernetes Pattern:**
```json
{
  "saService": {
    "serverAddress": "boulder-sa:9395",
    "hostOverride": "sa.boulder"
  }
}
```

#### PKI Certificate Hierarchy

**WebPKI Hierarchy (Certificate Issuance):**
```
Root CA (RSA/ECDSA)
├── Intermediate CA (RSA-A)
├── Intermediate CA (RSA-B)
└── Intermediate CA (ECDSA-A)
```

**Internal PKI (Service mTLS):**
```
Internal CA (minica)
├── boulder-sa.boulder
├── boulder-ca.boulder
├── boulder-ra.boulder
└── ... (one per service)
```

---

## HSM Implementation (Phase 1)

### SoftHSM Sidecar Architecture

Phase 1 uses a PKCS#11 proxy + SoftHSM sidecar pattern:

```
Boulder CA Pod
├── boulder-k8s:latest (main container)
│   └── PKCS#11 calls → localhost:2345
└── debian:12 sidecar
    ├── pkcs11-proxy (listens on :2345)
    ├── SoftHSM2 backend
    └── Token storage: /var/lib/softhsm/tokens/
```

### Key Features

- **Shared Storage**: ReadWriteMany PV for token persistence across CA replicas
- **Proxy Communication**: Boulder calls standard localhost:2345 PKCS#11 endpoint
- **Development Appropriate**: Uses SoftHSM matching Boulder's test environment
- **Phase 2 Ready**: Sidecar can be swapped for network HSM without Boulder changes

### PKCS#11 Configuration

```json
{
  "module": "localhost:2345",
  "tokenLabel": "intermediate-ca", 
  "pin": "1234",
  "privateKeyLabel": "intermediate-key"
}
```

---

## Health Checks and Monitoring

### Health Check Strategy

All services expose health endpoints on their debug ports:

```yaml
livenessProbe:
  httpGet:
    path: /debug/health
    port: 8003  # Debug port varies per service
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /debug/health  
    port: 8003
  initialDelaySeconds: 5
  periodSeconds: 5
```

### Key Monitoring Metrics

- **Service Health**: All `/debug/health` endpoints returning 200
- **Certificate Issuance Rate**: Certificates issued per minute
- **Validation Success Rate**: Challenge validation statistics
- **Database Performance**: Connection pool usage and query latency
- **Redis Memory**: Memory usage and eviction rates
- **Request Latency**: P50, P95, P99 latencies per service

---

## Infrastructure Services

### Database Architecture

- **MariaDB**: Primary database deployed as StatefulSet with persistent storage
- **ProxySQL**: Connection pooling and load balancing between Boulder services and MariaDB
- **Access Pattern**: All Boulder services connect through ProxySQL, never directly to MariaDB

### Redis Configuration

- **Instances**: 2 StatefulSets for rate limiting data sharding
- **Purpose**: Distributed rate limiting with ring topology
- **Authentication**: Password-based via Kubernetes Secrets

---

## Security Implementation

### mTLS Certificate Management

All Boulder gRPC services require mTLS certificates:

| File | Purpose | Mount Path |
|------|---------|------------|
| `minica.pem` | Internal CA certificate | `/etc/boulder/certs/minica.pem` |
| `{service}.boulder/cert.pem` | Service certificate | `/etc/boulder/certs/{service}.boulder/cert.pem` |
| `{service}.boulder/key.pem` | Service private key | `/etc/boulder/certs/{service}.boulder/key.pem` |

### Network Policies

Services communicate only with declared dependencies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: boulder-ra-network-policy
spec:
  podSelector:
    matchLabels:
      app: boulder-ra
  policyTypes: [Ingress, Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: boulder-sa
    - podSelector:
        matchLabels:
          app: boulder-ca
```

---

## Deployment Patterns

### Init Container Pattern

Ensure dependencies are ready before service startup:

```yaml
initContainers:
- name: wait-for-dependencies
  image: busybox:1.35
  command: ['sh', '-c']
  args:
    - |
      echo "Waiting for dependencies..."
      until nslookup boulder-sa.boulder.svc.cluster.local; do
        echo "Waiting for SA service..."
        sleep 2
      done
      echo "Dependencies ready!"
```

### Resource Requirements

Based on Boulder production metrics:

| Service Category | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------------|-------------|-----------|----------------|--------------|
| **Core Services** | 500m-1000m | 2000m-4000m | 512Mi-1Gi | 2Gi-4Gi |
| **Support Services** | 100m-200m | 500m-1000m | 128Mi-256Mi | 512Mi-1Gi |
| **Infrastructure** | 500m-1000m | 2000m-4000m | 512Mi-2Gi | 2Gi-8Gi |

---

## Testing and Validation

### Integration Testing

The deployment is validated by running Boulder's complete integration test suite:

```bash
# Deploy integration test job
kubectl apply -f k8s/jobs/boulder-integration-test.yaml

# Monitor test execution  
kubectl wait --for=condition=complete job/integration-test -n boulder --timeout=30m
```

### Test Coverage

- **ACME Workflow**: Complete certificate issuance process
- **Challenge Types**: HTTP-01, DNS-01, TLS-ALPN-01 validation
- **Multi-Perspective**: MPIC validation from multiple network perspectives
- **Security**: mTLS authentication between services
- **Performance**: Rate limiting and load balancing functionality

### Success Criteria

- All service pods running and healthy
- Database connectivity through ProxySQL established
- mTLS communication between services functional
- HSM certificate signing operational
- Integration test suite passes (100% success rate)

---

## Operational Procedures

### Deployment Sequence

```bash
# 1. Create cluster and build images
kind create cluster --name boulder-k8s --config kind-config.yaml
make docker-build

# 2. Deploy infrastructure
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/deployments/infrastructure/
./k8s/scripts/health-check.sh --wait-infrastructure

# 3. Deploy Boulder services (dependency order)
kubectl apply -f k8s/deployments/boulder/
./k8s/scripts/health-check.sh --verbose

# 4. Run integration tests
./k8s/scripts/run-integration-tests.sh
```

### Health Validation

```bash
# Check service health endpoints
for service in sa ca ra va wfe2; do
  kubectl exec deployment/boulder-$service -n boulder -- \
    curl -sf http://localhost:800X/debug/health
done

# Verify certificate functionality
kubectl exec deployment/boulder-ca -n boulder -- \
  ls -la /etc/boulder/webpki/ /var/lib/softhsm/tokens/
```

### Configuration Updates

```bash
# Update service configuration
kubectl patch configmap boulder-ra-config -n boulder --type merge -p \
  '{"data":{"ra.json":"updated-config-content"}}'

# Rolling restart to pick up changes
kubectl rollout restart deployment/boulder-ra -n boulder
```

---

## Performance and Scaling

### Resource Optimization

- **Database Connection Pooling**: ProxySQL manages connection limits and query routing
- **Redis Sharding**: Distributed rate limiting across multiple Redis instances  
- **Horizontal Scaling**: Core services run multiple instances for load distribution
- **Pod Resource Limits**: Based on Boulder production performance metrics

### Scaling Strategy

- **WFE2 Scaling**: Increase replicas based on ACME API request volume
- **RA Scaling**: Scale Registration Authority instances for certificate issuance load
- **Database Optimization**: ProxySQL connection tuning and query optimization
- **Redis Memory**: Configure appropriate memory limits and eviction policies

---

## Phase 2 Transition Considerations

### Network HSM Integration

Phase 1 SoftHSM sidecar enables seamless Phase 2 transition:

- **Current**: SoftHSM sidecar with local token storage
- **Phase 2**: Network HSM proxy sidecar with remote HSM connectivity
- **Boulder Impact**: Zero changes required in Boulder containers

### Security Hardening

Phase 2 will build upon Phase 1 security foundation:

- **Pod Security Standards**: Enhanced security contexts and capability restrictions
- **Network Policies**: Fine-grained traffic restriction based on service dependencies
- **Runtime Security**: Container image scanning and runtime threat detection
- **Secrets Encryption**: Enhanced encryption at rest for sensitive data

### Multi-Cluster Architecture

Phase 2 considerations for production scaling:

- **Cross-region Deployment**: Database replication and geographic distribution
- **Global Load Balancing**: Intelligent traffic routing across regions
- **Disaster Recovery**: Automated failover and backup procedures
- **Compliance**: Enhanced logging and auditing for production environments

---

## References

### Key Documents

- [`reference/SPECp1.md`](../reference/SPECp1.md) - **Authoritative Phase 1 specification**
- [`architecture/shared/service-matrix.md`](shared/service-matrix.md) - Complete service specifications
- [`architecture/shared/decisions.md`](shared/decisions.md) - Architectural decision records
- [`reference/BOULDER.md`](../reference/BOULDER.md) - Upstream Boulder technical reference

### OCSP Exclusion

**Important:** This implementation excludes all OCSP functionality as documented in [Decision 1: OCSP Functionality Exclusion](shared/decisions.md#decision-1-ocsp-functionality-exclusion).

### Implementation Decisions

All major architectural decisions are documented in [`architecture/shared/decisions.md`](shared/decisions.md):

- HSM sidecar implementation in Phase 1
- mTLS as core requirement  
- Service port standardization
- Directory structure standards
- Documentation consolidation strategy