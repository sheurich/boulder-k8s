# Boulder Kubernetes Implementation Plan

## Overview

This document outlines the phased implementation approach for deploying Boulder ACME CA to Kubernetes. The plan follows a bottom-up strategy, building infrastructure first, then core services, and finally testing the complete system.

## Project Directory Structure

Following the authoritative structure specified in `reference/SPECp1.md`:

```
boulder-k8s/
├── README.md                           # Project documentation
├── Makefile                           # Build and deployment targets
├── architecture/                      # Architectural documentation
│   ├── phase1/
│   │   ├── overview.md                # Phase 1 architecture overview
│   │   ├── implementation-guide.md    # This document
│   │   └── hsm-implementation-plan.md # HSM implementation for Phase 1
│   ├── phase2/
│   │   └── hsm-security-architecture.md # Production HSM architecture
│   └── shared/
│       └── service-matrix.md          # Service specifications
├── scripts/                           # Helper scripts
│   ├── generate-certs.sh             # PKI certificate generation
│   ├── wait-for-dependencies.sh      # Dependency checking
│   └── verify-deployment.sh          # Deployment validation
└── manifests/                         # Kubernetes manifests
    ├── namespace.yaml
    ├── infrastructure/
    │   ├── cert-manager/              # Certificate manager setup
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
    │   ├── pki/                       # Internal PKI certificates
    │   └── network-policies/          # Phase 2 network policies
    ├── data/
    │   └── database-init-job.yaml     # Database initialization
    ├── shared/
    │   ├── secrets.yaml               # Combined secrets manifest
    │   └── rbac.yaml                  # RBAC configuration
    └── tests/
        └── integration-test-job.yaml   # Integration test job
```

**Note**: This structure follows SPECp1.md as the authoritative source and eliminates redundant top-level directories that were causing confusion.

## Implementation Phases

### Phase 0: Prerequisites and Setup
**Duration: 1-2 hours**

#### Tasks:
1. **Setup Kind cluster**
   ```bash
   kind create cluster --name boulder-k8s --config kind-config.yaml
   ```

2. **Build Boulder container image**
   - Use existing Boulder Dockerfile/Containerfile
   - Build single image with all Boulder components
   - Push to local registry or load into Kind

3. **Generate PKI certificates**
   - Run Boulder's `test/certs/generate.sh` script
   - Generate WebPKI hierarchy (root + intermediate certs)
   - Generate Internal PKI for mTLS
   - Package into Kubernetes Secrets

4. **Prepare configuration files**
   - Convert Boulder JSON configs from Docker Compose
   - Replace Consul SRV lookups with Kubernetes DNS
   - Update file paths for Kubernetes mounts

#### Validation:
- [ ] Kind cluster running
- [ ] Boulder image available in cluster
- [ ] All certificates generated
- [ ] Configuration files prepared

---

### Phase 1: Infrastructure Layer
**Duration: 1-2 hours**

#### Implementation Order:
1. **Namespace and RBAC**
   ```bash
   kubectl apply -f manifests/namespace.yaml
   kubectl apply -f manifests/shared/rbac.yaml
   ```

2. **MariaDB StatefulSet**
   - Deploy primary database
   - Wait for ready state
   - Run schema migrations

3. **Redis StatefulSets** (2 instances)
   - Deploy Redis for rate limiting
   - Configure sharding

4. **ProxySQL Deployment**
   - Deploy after MariaDB is ready
   - Configure connection pooling

#### Validation Checklist:
- [ ] MariaDB accepting connections
- [ ] Database schema migrated
- [ ] Redis instances responding
- [ ] ProxySQL routing to MariaDB
- [ ] All pods in Running state

#### Testing:
```bash
# Test database connectivity
kubectl exec -n boulder deployment/proxysql -- mysql -h127.0.0.1 -P6033 -uboulder -p$PASSWORD -e "SHOW DATABASES;"

# Test Redis connectivity
kubectl exec -n boulder statefulset/redis-1 -- redis-cli -a $REDIS_PASSWORD ping
```

---

### Phase 2: Foundation Services
**Duration: 2-3 hours**

#### Implementation Order:

1. **Remote VA Services** (Parallel)
   - Deploy remoteva-a, remoteva-b, remoteva-c
   - No dependencies, can deploy simultaneously
   ```bash
   kubectl apply -f manifests/boulder/remoteva/
   ```

2. **Storage Authority (SA)**
   - Deploy after ProxySQL is ready
   - 2 replicas (boulder-sa-1, boulder-sa-2)
   - Verify database connectivity
   ```bash
   kubectl apply -f manifests/boulder/sa/
   ```

3. **Publisher Service**
   - Deploy 2 replicas
   - No dependencies on other Boulder services
   ```bash
   kubectl apply -f manifests/boulder/publisher/
   ```

#### Validation Checklist:
- [ ] All Remote VA pods running
- [ ] SA services connected to database
- [ ] Publisher services ready
- [ ] Health checks passing

#### Testing:
```bash
# Check SA database connectivity
kubectl exec -n boulder deployment/boulder-sa -- curl -s http://localhost:8003/debug/health

# Verify Remote VA health
for va in a b c; do
  kubectl exec -n boulder deployment/remoteva-$va -- curl -s http://localhost:801${va}/debug/health
done
```

---

### Phase 3: Validation Layer
**Duration: 1-2 hours**

#### Implementation Order:

1. **Validation Authority (VA)**
   - Deploy after Remote VAs are ready
   - 2 replicas
   - Configure with Remote VA endpoints
   ```bash
   kubectl apply -f manifests/boulder/va/
   ```

#### Validation Checklist:
- [ ] VA pods running
- [ ] Connected to Remote VAs
- [ ] Health checks passing
- [ ] DNS resolution working

#### Testing:
```bash
# Test VA connectivity to Remote VAs
kubectl exec -n boulder deployment/boulder-va -- curl -s http://localhost:8004/debug/health
```

---

### Phase 4: Certificate Services
**Duration: 2-3 hours**

#### Implementation Order:

1. **SCT Provider (Specialized RA)**
   - Deploy after Publisher is ready
   - 2 replicas for SCT operations
   ```bash
   kubectl apply -f manifests/boulder/ra-sct-provider/
   ```

2. **Certificate Authority (CA)**
   - Deploy after SA and SCT Provider ready
   - 2 replicas
   - Mount WebPKI certificates
   - Verify HSM/PKCS#11 configuration
   ```bash
   kubectl apply -f manifests/boulder/ca/
   ```

#### Validation Checklist:
- [ ] SCT Provider connected to Publisher
- [ ] CA pods running
- [ ] WebPKI certificates mounted
- [ ] CA connected to SCT Provider
- [ ] Certificate signing operational

#### Testing:
```bash
# Verify CA has signing certificates
kubectl exec -n boulder deployment/boulder-ca -- ls -la /etc/boulder/webpki/

# Check CA health
kubectl exec -n boulder deployment/boulder-ca -- curl -s http://localhost:8001/debug/health
```

---

### Phase 5: Registration Services
**Duration: 2-3 hours**

#### Implementation Order:

1. **Registration Authority (RA)**
   - Deploy after CA, VA, SA, Publisher ready
   - 2 replicas
   - Most complex service with many dependencies
   ```bash
   kubectl apply -f manifests/boulder/ra/
   ```

#### Validation Checklist:
- [ ] RA connected to all dependencies
- [ ] Rate limiting via Redis working
- [ ] Policy enforcement configured
- [ ] Health checks passing

#### Testing:
```bash
# Verify RA connectivity
kubectl exec -n boulder deployment/boulder-ra -- curl -s http://localhost:8002/debug/health

# Check service dependencies
kubectl exec -n boulder deployment/boulder-ra -- nslookup boulder-sa
kubectl exec -n boulder deployment/boulder-ra -- nslookup boulder-ca
kubectl exec -n boulder deployment/boulder-ra -- nslookup boulder-va
```

---

### Phase 6: Web Services
**Duration: 2-3 hours**

#### Implementation Order:

1. **Nonce Service**
   - Deploy after Redis is ready
   - 2-4 replicas for geographic distribution
   ```bash
   kubectl apply -f manifests/boulder/nonce-service/
   ```

2. **Web Front End (WFE2)**
   - Deploy after RA, SA, Nonce Service ready
   - Public-facing ACME API
   - Configure Ingress for external access
   ```bash
   kubectl apply -f manifests/boulder/wfe2/
   ```

3. **Self-service Front End (SFE)**
   - Deploy after RA, SA ready
   - Optional web portal
   ```bash
   kubectl apply -f manifests/boulder/sfe/
   ```

#### Validation Checklist:
- [ ] Nonce Service connected to Redis
- [ ] WFE2 accessible via Ingress
- [ ] ACME endpoints responding
- [ ] SFE portal accessible

#### Testing:
```bash
# Test ACME directory endpoint
curl -s http://localhost:4001/directory | jq .

# Verify nonce generation
curl -I http://localhost:4001/acme/new-nonce
```

---

### Phase 7: Support Services
**Duration: 1-2 hours**

#### Implementation Order (Can deploy in parallel):

1. **CRL Storer**
2. **Bad Key Revoker**
3. **Log Validator**
4. **Email Exporter**

```bash
kubectl apply -f manifests/support/
```

#### Validation Checklist:
- [ ] All support services running
- [ ] Connected to SA
- [ ] Health checks passing

---

### Phase 8: Testing and Validation
**Duration: 2-4 hours**

#### Test Categories:

1. **Service Health Verification**
   ```bash
   ./scripts/verify-deployment.sh
   ```

2. **ACME Workflow Test**
   - Create test account
   - Request authorization
   - Complete challenge
   - Issue certificate

3. **Integration Test Suite**
   ```bash
   # Run Boulder's integration tests
   kubectl apply -f manifests/tests/integration-job.yaml
   kubectl wait --for=condition=complete job/integration-test -n boulder --timeout=30m
   ```

4. **Challenge Type Testing**
   - HTTP-01 challenge
   - DNS-01 challenge
   - TLS-ALPN-01 challenge

5. **Load Testing**
   - Concurrent certificate requests
   - Rate limiting verification
   - Performance baseline

#### Success Criteria:
- [ ] All services healthy
- [ ] Integration tests passing
- [ ] Certificate issuance working
- [ ] All challenge types validated
- [ ] Rate limiting functional
- [ ] Monitoring/metrics available

---

## Rollback Strategy

### Service-Level Rollback
```bash
# Rollback specific service
kubectl rollout undo deployment/boulder-ra -n boulder

# Check rollback status
kubectl rollout status deployment/boulder-ra -n boulder
```

### Full Environment Rollback
```bash
# Delete all Boulder services
kubectl delete namespace boulder

# Restore from backup
./scripts/restore-from-backup.sh
```

---

## Configuration Management Strategy

### ConfigMap Updates
1. **Non-Breaking Changes**: Update ConfigMap and restart pods
   ```bash
   kubectl apply -f manifests/boulder/ra/configmap.yaml
   kubectl rollout restart deployment/boulder-ra -n boulder
   ```

2. **Breaking Changes**: Use blue-green deployment
   - Deploy new version alongside old
   - Switch traffic after validation
   - Remove old version

### Secret Rotation
1. **Certificate Rotation**:
   - Generate new certificates
   - Update Secrets
   - Rolling restart of affected services

2. **Database Credential Rotation**:
   - Update credentials in database
   - Update Kubernetes Secrets
   - Rolling restart SA services

---

## Monitoring and Observability

### Key Metrics to Track During Implementation

#### Phase Metrics:
- Deployment duration per phase
- Service startup time
- Dependency resolution time
- Error rates during startup

#### Service Metrics:
- Pod ready time
- Health check latency
- Inter-service connectivity
- Resource utilization

### Monitoring Setup:
```yaml
# Prometheus ServiceMonitor example
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: boulder-services
  namespace: boulder
spec:
  selector:
    matchLabels:
      app: boulder
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### Service Won't Start
1. Check logs: `kubectl logs -n boulder deployment/SERVICE_NAME`
2. Verify dependencies: `kubectl exec -n boulder deployment/SERVICE_NAME -- nslookup DEPENDENCY`
3. Check configuration: `kubectl describe configmap SERVICE_NAME-config -n boulder`

#### Database Connection Issues
1. Verify ProxySQL is running
2. Check database credentials in Secrets
3. Test connectivity from SA pod

#### Certificate Issues
1. Verify WebPKI certificates are mounted
2. Check PKCS#11 configuration
3. Ensure CA has access to signing keys

#### Network Issues
1. Check Service endpoints: `kubectl get endpoints -n boulder`
2. Verify DNS resolution
3. Check NetworkPolicies if enabled

---

## Automation Scripts

### deploy.sh - One-Command Deployment
```bash
#!/bin/bash
set -e

echo "=== Boulder Kubernetes Deployment ==="

# Phase 0: Prerequisites
echo "Setting up prerequisites..."
./scripts/generate-certs.sh
kubectl apply -f manifests/namespace.yaml

# Phase 1: Infrastructure
echo "Deploying infrastructure..."
kubectl apply -f manifests/infrastructure/
./scripts/wait-for-dependencies.sh infrastructure

# Phase 2-7: Service Deployment
for phase in foundation validation certificate registration web support; do
  echo "Deploying $phase services..."
  kubectl apply -f manifests/boulder/$phase/
  ./scripts/wait-for-dependencies.sh $phase
done

# Phase 8: Validation
echo "Running validation..."
./scripts/verify-deployment.sh

echo "=== Deployment Complete ==="
```

### test.sh - Integration Test Runner
```bash
#!/bin/bash
set -e

echo "=== Running Boulder Integration Tests ==="

# Deploy test job
kubectl apply -f manifests/tests/integration-job.yaml

# Wait for completion
kubectl wait --for=condition=complete \
  job/integration-test -n boulder \
  --timeout=30m

# Get results
kubectl logs job/integration-test -n boulder

echo "=== Tests Complete ==="
```

---

## Risk Mitigation

### Technical Risks

1. **Service Discovery Issues**
   - Risk: Kubernetes DNS not resolving correctly
   - Mitigation: Use IP addresses as fallback
   - Testing: DNS resolution tests in init containers

2. **Certificate Management**
   - Risk: Certificate expiration or misconfiguration
   - Mitigation: Automated rotation, monitoring alerts
   - Testing: Certificate validation in health checks

3. **Database Performance**
   - Risk: Connection pool exhaustion
   - Mitigation: ProxySQL tuning, connection limits
   - Testing: Load testing during Phase 8

4. **Network Policies**
   - Risk: Over-restrictive policies blocking communication
   - Mitigation: Start permissive, gradually restrict
   - Testing: Connectivity matrix validation

### Operational Risks

1. **Deployment Failures**
   - Risk: Partial deployment leaving system inconsistent
   - Mitigation: Atomic phase deployments, rollback capability
   - Testing: Failure injection testing

2. **Configuration Drift**
   - Risk: Manual changes causing inconsistency
   - Mitigation: GitOps, configuration validation
   - Testing: Configuration compliance checks

---

## Success Metrics

### Deployment Success Criteria
- All 15+ Boulder services running and healthy
- Integration test suite passing (100% pass rate)
- ACME endpoints accessible and responding
- Certificate issuance successful for all challenge types
- Rate limiting functional
- Monitoring and metrics available

### Performance Baselines
- Service startup: < 60 seconds per service
- Health check response: < 100ms
- Certificate issuance: < 10 seconds end-to-end
- Challenge validation: < 5 seconds
- Database query latency: < 50ms p99

### Operational Metrics
- Deployment time: < 30 minutes total
- Recovery time objective (RTO): < 15 minutes
- Recovery point objective (RPO): < 1 hour
- Availability: > 99.9% for critical services

---

## Next Steps and Phase 2 Considerations

### Immediate Next Steps (Phase 1 Completion)
1. Implement Kubernetes manifests following this plan
2. Create deployment and test scripts
3. Document operational procedures
4. Set up monitoring and alerting

### Future Enhancements (Phase 2)
1. **Network HSM Integration**
   - Replace file-based PKCS#11 with network HSM
   - Implement SoftHSM2 + pkcs11-proxy

2. **Multi-Cluster Deployment**
   - Cross-region replication
   - Global load balancing
   - Disaster recovery

3. **Advanced Observability**
   - Custom Grafana dashboards
   - Distributed tracing with Jaeger
   - Advanced alerting rules

4. **Security Hardening**
   - Pod Security Standards enforcement
   - Runtime security scanning
   - Secrets encryption at rest

5. **Performance Optimization**
   - Horizontal Pod Autoscaling
   - Resource optimization
   - Cache layer implementation

---

## Conclusion

This implementation plan provides a systematic approach to deploying Boulder on Kubernetes. The phased approach ensures each layer is properly established before building upon it, minimizing deployment risks and ensuring a stable, production-ready ACME CA environment.

The plan prioritizes:
- **Correctness**: Ensuring all services start in the right order
- **Observability**: Validation at each phase
- **Maintainability**: Clear structure and documentation
- **Reliability**: Comprehensive testing before completion

Following this plan will result in a fully functional Boulder ACME CA running on Kubernetes, ready for certificate issuance and passing all integration tests.
