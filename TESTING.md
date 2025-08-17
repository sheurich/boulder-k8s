# Boulder Kubernetes Testing Guide

This document provides comprehensive testing procedures for Boulder ACME CA deployed on Kubernetes, covering health checks, integration tests, and validation procedures.

## Table of Contents

- [Testing Philosophy](#testing-philosophy)
- [Testing Framework Overview](#testing-framework-overview)
- [Health Checks](#health-checks)
- [Integration Testing](#integration-testing)
- [Manual Testing](#manual-testing)
- [Test Automation](#test-automation)
- [Debugging Failed Tests](#debugging-failed-tests)
- [Adding New Tests](#adding-new-tests)
- [Performance Testing](#performance-testing)
- [Security Testing](#security-testing)

## Testing Philosophy

Boulder Kubernetes testing follows a comprehensive multi-layer approach:

### Testing Principles

1. **OCSP Exclusion**: All tests exclude OCSP functionality (deprecated in Boulder)
2. **Service Dependencies**: Tests validate proper service startup order and dependencies
3. **ACME Compliance**: Complete ACME protocol workflow validation
4. **Multi-Perspective**: Validation from multiple network perspectives (MPIC)
5. **Real-World Scenarios**: Tests simulate actual certificate issuance workflows

### Testing Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Integration Tests                         │
│              (Full ACME Workflow Validation)               │
├─────────────────────────────────────────────────────────────┤
│                     API Tests                              │
│            (Individual Endpoint Validation)                │
├─────────────────────────────────────────────────────────────┤
│                   Health Checks                            │
│         (Service Readiness and Connectivity)               │
├─────────────────────────────────────────────────────────────┤
│                Infrastructure Tests                         │
│          (Database, Redis, Network Connectivity)           │
└─────────────────────────────────────────────────────────────┘
```

## Testing Framework Overview

### Test Categories

| Test Type | Purpose | Frequency | Scope |
|-----------|---------|-----------|-------|
| **Health Checks** | Service readiness validation | Continuous | Individual services |
| **Integration Tests** | End-to-end ACME workflow | On deployment | Complete system |
| **API Tests** | ACME endpoint validation | On changes | API layer |
| **Load Tests** | Performance under load | Periodic | System capacity |
| **Security Tests** | Security vulnerability scanning | On changes | Security posture |

### Test Tools

- **Health Checks**: Custom shell scripts with kubectl
- **Integration Tests**: Boulder's existing Python test suite
- **API Tests**: curl, ACME clients (certbot, acme.sh)
- **Load Tests**: Artillery, k6, or custom load generators
- **Security Tests**: Network policies, vulnerability scanners

## Health Checks

Health checks validate that all Boulder services are running correctly and can communicate with their dependencies.

### Running Health Checks

#### Basic Health Check

```bash
# Run basic health check
./k8s/scripts/health-check.sh

# Expected output:
# ✓ kubectl is available
# ✓ Connected to cluster: kind-boulder-k8s
# ✓ Namespace 'boulder' exists
# ✓ Infrastructure services are healthy
# ✓ Boulder services are healthy
# ✓ Database connectivity is healthy
# ✓ Redis connectivity is healthy
# ✓ ACME API endpoint is healthy
```

#### Detailed Health Check

```bash
# Run with verbose output and resource usage
./k8s/scripts/health-check.sh --verbose --resources

# Shows:
# - Detailed pod status
# - Service endpoints
# - Resource usage metrics
# - Recent service logs
```

#### Health Check Options

```bash
# Show help
./k8s/scripts/health-check.sh --help

# Available options:
--verbose, -v     Show detailed pod and service status
--resources, -r   Show resource usage information
--logs           Show recent logs from all services
```

### Health Check Components

#### Infrastructure Validation

Tests core infrastructure services:

```bash
# MariaDB readiness
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
    statefulset/mariadb -n boulder --timeout=30s

# Redis connectivity (both instances)
kubectl exec -n boulder statefulset/redis-0 -- redis-cli ping
kubectl exec -n boulder statefulset/redis-1 -- redis-cli ping

# ProxySQL database proxy
kubectl exec -n boulder deployment/proxysql -- nc -z localhost 6033
```

#### Boulder Service Validation

Tests all Boulder services:

```bash
# Service availability
kubectl wait --for=condition=available \
    deployment/boulder-wfe2 -n boulder --timeout=30s

# Health endpoint responses
kubectl exec -n boulder deployment/boulder-wfe2 -- \
    wget -q --spider http://localhost:8013/debug/health
```

#### ACME API Validation

Tests public ACME endpoints:

```bash
# Directory endpoint
curl -s http://localhost:4001/directory | jq .

# Nonce generation
curl -I http://localhost:4001/acme/new-nonce
```

### Health Check Troubleshooting

#### Service Not Ready

```bash
# Check pod status
kubectl describe pod <pod-name> -n boulder

# Check service logs
kubectl logs deployment/<service-name> -n boulder --tail=50

# Check resource constraints
kubectl top pods -n boulder
```

#### Database Connectivity Issues

```bash
# Test direct database connection
kubectl exec -n boulder statefulset/mariadb -- \
    mysqladmin ping -h localhost

# Test ProxySQL connectivity
kubectl exec -n boulder deployment/proxysql -- \
    nc -zv mariadb 3306
```

## Integration Testing

Integration tests validate the complete ACME certificate issuance workflow using Boulder's existing test suite.

### Running Integration Tests

#### Basic Integration Test

```bash
# Run complete integration test suite
./k8s/scripts/run-integration-tests.sh

# Monitor test progress
kubectl logs -f job/boulder-integration-test -n boulder
```

#### Integration Test Options

```bash
# Show help
./k8s/scripts/run-integration-tests.sh --help

# Available options:
--no-cleanup      Skip cleanup of test resources after completion
--timeout TIMEOUT Set test timeout (default: 1800s)
```

#### Custom Timeout

```bash
# Run with extended timeout for slow environments
./k8s/scripts/run-integration-tests.sh --timeout 3600s
```

### Integration Test Components

#### Test Workflow

The integration test validates:

1. **Account Creation**: ACME account registration
2. **Order Placement**: Certificate order creation
3. **Challenge Processing**: HTTP-01, DNS-01, TLS-ALPN-01 challenges
4. **Multi-Perspective Validation**: Validation from multiple network locations
5. **Certificate Issuance**: Certificate signing and delivery
6. **Certificate Revocation**: Certificate revocation workflow

#### Test Scenarios

```bash
# Individual test categories (if running manually):

# HTTP-01 Challenge
python3 test/integration-test.py --chisel --filter test_http_challenge

# DNS-01 Challenge  
python3 test/integration-test.py --chisel --filter test_dns_challenge

# TLS-ALPN-01 Challenge
python3 test/integration-test.py --chisel --filter test_tls_alpn_challenge

# Multi-domain certificates
python3 test/integration-test.py --chisel --filter test_multidomain

# Certificate revocation
python3 test/integration-test.py --chisel --filter test_revocation
```

### Integration Test Execution

#### Test Job Definition

The integration test runs as a Kubernetes Job:

```yaml
# k8s/jobs/boulder-integration-test.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: boulder-integration-test
  namespace: boulder
spec:
  template:
    spec:
      containers:
      - name: integration-test
        image: boulder:local
        command: ["python3", "test/integration-test.py", "--chisel"]
        env:
        - name: BOULDER_WFE2_ENDPOINT
          value: "http://boulder-wfe2:4001"
```

#### Test Monitoring

```bash
# Check test job status
kubectl get job boulder-integration-test -n boulder

# Monitor test pod
kubectl get pods -n boulder -l job-name=boulder-integration-test

# View real-time logs
kubectl logs -f job/boulder-integration-test -n boulder

# Check test completion
kubectl wait --for=condition=complete \
    job/boulder-integration-test -n boulder --timeout=1800s
```

### Integration Test Results

#### Success Criteria

A successful integration test run should show:
- All ACME workflow steps complete without errors
- Certificates issued for all challenge types
- Multi-perspective validation successful
- Certificate revocation functional
- No OCSP-related test failures (excluded as intended)

#### Sample Output

```
Starting Boulder integration tests...
✓ Account registration successful
✓ HTTP-01 challenge validation passed
✓ DNS-01 challenge validation passed  
✓ TLS-ALPN-01 challenge validation passed
✓ Multi-domain certificate issued
✓ Certificate revocation successful
✓ Multi-perspective validation working
Integration tests completed: 47 passed, 0 failed, 0 skipped
OCSP tests skipped (deprecated functionality)
```

## Manual Testing

Manual testing allows validation of specific ACME functionality and troubleshooting of issues.

### ACME Client Testing

#### Using certbot

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

# Request certificate (DNS-01 challenge)
certbot certonly \
    --server http://localhost:4001/acme/directory \
    --manual \
    --preferred-challenges dns \
    --domains test.example.com
```

#### Using acme.sh

```bash
# Register and request certificate
acme.sh --issue \
    --server http://localhost:4001/acme/directory \
    --domain test.example.com \
    --standalone

# Request wildcard certificate
acme.sh --issue \
    --server http://localhost:4001/acme/directory \
    --domain "*.example.com" \
    --dns dns_manual
```

### API Endpoint Testing

#### Directory Endpoint

```bash
# Test ACME directory
curl -s http://localhost:4001/directory | jq .

# Expected structure:
{
  "newAccount": "http://localhost:4001/acme/new-account",
  "newNonce": "http://localhost:4001/acme/new-nonce", 
  "newOrder": "http://localhost:4001/acme/new-order",
  "revokeCert": "http://localhost:4001/acme/revoke-cert",
  "keyChange": "http://localhost:4001/acme/key-change"
}
```

#### Nonce Generation

```bash
# Get fresh nonce
curl -I http://localhost:4001/acme/new-nonce

# Check for Replay-Nonce header
HTTP/1.1 200 OK
Replay-Nonce: <base64-encoded-nonce>
Cache-Control: no-store
```

#### Account Creation

```bash
# Create test account (requires proper ACME client implementation)
# This is complex - use existing ACME client tools instead
```

### Service-Specific Testing

#### Database Operations

```bash
# Test Storage Authority database connectivity
kubectl exec -n boulder deployment/boulder-sa -- \
    nc -zv proxysql 6033

# Check database schema (if accessible)
kubectl exec -n boulder statefulset/mariadb -- \
    mysql -u boulder -p -e "SHOW TABLES;" boulder
```

#### Certificate Authority

```bash
# Verify CA has signing certificates
kubectl exec -n boulder deployment/boulder-ca -- \
    ls -la /etc/boulder/webpki/

# Check certificate validity
kubectl exec -n boulder deployment/boulder-ca -- \
    openssl x509 -in /etc/boulder/webpki/int-rsa-a.cert.pem -text -noout
```

#### Validation Authority

```bash
# Test VA connectivity to Remote VAs
kubectl exec -n boulder deployment/boulder-va -- \
    nc -zv remote-va1 9397

# Check DNS resolver configuration
kubectl exec -n boulder deployment/boulder-va -- \
    nslookup google.com
```

## Test Automation

### Makefile Targets

The project includes Makefile targets for common testing tasks:

```bash
# Run all tests
make test

# Run health checks only
make test-health

# Run integration tests only
make test-integration

# Run linting (part of quality assurance)
make lint
```

### Continuous Integration

Integration with CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
name: Boulder K8s Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup kind
        uses: helm/kind-action@v1.8.0
        with:
          cluster_name: boulder-test
          
      - name: Deploy Boulder
        run: ./k8s/scripts/deploy.sh
        
      - name: Run Health Checks
        run: ./k8s/scripts/health-check.sh --verbose
        
      - name: Run Integration Tests
        run: ./k8s/scripts/run-integration-tests.sh
```

### Automated Test Scheduling

```bash
# Example CronJob for periodic testing
kubectl create cronjob boulder-health-check \
    --image=boulder:local \
    --schedule="*/15 * * * *" \
    --restart=OnFailure \
    -- /bin/bash -c "./k8s/scripts/health-check.sh"
```

## Debugging Failed Tests

### Common Test Failures

#### Service Startup Issues

```bash
# Check pod events
kubectl describe pod <failing-pod> -n boulder

# Check service logs
kubectl logs deployment/<service> -n boulder --previous

# Check resource constraints
kubectl top pods -n boulder
kubectl describe node <node-name>
```

#### Network Connectivity Issues

```bash
# Test internal service connectivity
kubectl exec -n boulder deployment/boulder-wfe2 -- \
    nc -zv boulder-ra 9394

# Check DNS resolution
kubectl exec -n boulder deployment/boulder-wfe2 -- \
    nslookup boulder-ra.boulder.svc.cluster.local

# Verify service endpoints
kubectl get endpoints -n boulder
```

#### Database Connection Failures

```bash
# Check database pod status
kubectl get pods -n boulder -l app=mariadb

# Test database connectivity
kubectl exec -n boulder statefulset/mariadb -- \
    mysqladmin ping -h localhost

# Check ProxySQL configuration
kubectl logs deployment/proxysql -n boulder
```

#### Certificate Issues

```bash
# Check certificate secrets
kubectl get secrets -n boulder | grep -E "(webpki|internal)"

# Verify certificate mounts
kubectl exec -n boulder deployment/boulder-ca -- \
    ls -la /etc/boulder/webpki/ /etc/boulder/certs/

# Check certificate validity
kubectl exec -n boulder deployment/boulder-ca -- \
    openssl x509 -in /etc/boulder/webpki/int-rsa-a.cert.pem -enddate -noout
```

### Test Log Analysis

#### Integration Test Logs

```bash
# Get complete integration test logs
kubectl logs job/boulder-integration-test -n boulder > test-logs.txt

# Search for specific errors
grep -i error test-logs.txt
grep -i failed test-logs.txt
grep -i timeout test-logs.txt
```

#### Service Logs

```bash
# Get logs from all Boulder services
for service in wfe2 ra sa ca va publisher; do
    echo "=== boulder-$service ==="
    kubectl logs deployment/boulder-$service -n boulder --tail=50
done > boulder-service-logs.txt
```

#### Infrastructure Logs

```bash
# Database logs
kubectl logs statefulset/mariadb -n boulder --tail=100

# Redis logs
kubectl logs statefulset/redis-0 -n boulder --tail=50
kubectl logs statefulset/redis-1 -n boulder --tail=50

# ProxySQL logs
kubectl logs deployment/proxysql -n boulder --tail=100
```

## Adding New Tests

### Health Check Extensions

To add new health checks to the existing framework:

```bash
# Edit k8s/scripts/health-check.sh
# Add new function following existing patterns:

check_new_feature() {
    echo -e "${BLUE}Checking new feature...${NC}"
    local feature_health=0
    
    # Add specific checks here
    if kubectl exec -n boulder deployment/service -- test-command; then
        echo -e "${GREEN}✓ New feature is healthy${NC}"
    else
        echo -e "${RED}✗ New feature has issues${NC}"
        feature_health=1
    fi
    
    return $feature_health
}
```

### Integration Test Extensions

To add new integration tests:

```bash
# Create new test file in Boulder source
# File: test/integration-test-custom.py

import subprocess
import pytest

def test_custom_acme_workflow():
    """Test custom ACME functionality"""
    # Implement test logic
    result = subprocess.run([
        "curl", "-s", "http://boulder-wfe2:4001/directory"
    ], capture_output=True, text=True)
    
    assert result.returncode == 0
    assert "newAccount" in result.stdout
```

### Custom Test Jobs

Create custom Kubernetes test jobs:

```yaml
# custom-test-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: custom-boulder-test
  namespace: boulder
spec:
  template:
    spec:
      containers:
      - name: custom-test
        image: boulder:local
        command: ["python3", "test/custom-test.py"]
        env:
        - name: BOULDER_WFE2_ENDPOINT
          value: "http://boulder-wfe2:4001"
      restartPolicy: Never
  backoffLimit: 3
```

## Performance Testing

### Load Testing

#### Using Artillery

```bash
# Install Artillery
npm install -g artillery

# Create load test configuration
cat > boulder-load-test.yml << EOF
config:
  target: 'http://localhost:4001'
  phases:
    - duration: 60
      arrivalRate: 10
scenarios:
  - name: "ACME Directory"
    requests:
      - get:
          url: "/directory"
EOF

# Run load test
artillery run boulder-load-test.yml
```

#### Using k6

```javascript
// boulder-load-test.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 0 },
  ],
};

export default function() {
  let response = http.get('http://localhost:4001/directory');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
```

### Resource Monitoring

```bash
# Monitor resource usage during tests
kubectl top pods -n boulder --sort-by=cpu
kubectl top pods -n boulder --sort-by=memory

# Monitor node resources
kubectl top nodes

# Get detailed metrics (if metrics-server installed)
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/boulder/pods
```

## Security Testing

### Network Policy Validation

```bash
# Test network isolation
kubectl exec -n boulder deployment/boulder-wfe2 -- \
    nc -zv boulder-ca 9393  # Should succeed

kubectl exec -n boulder deployment/boulder-wfe2 -- \
    nc -zv mariadb 3306     # Should fail (if network policies applied)
```

### Certificate Security

```bash
# Check certificate algorithms
kubectl exec -n boulder deployment/boulder-ca -- \
    openssl x509 -in /etc/boulder/webpki/int-rsa-a.cert.pem -text -noout | \
    grep "Signature Algorithm"

# Verify certificate chain
kubectl exec -n boulder deployment/boulder-ca -- \
    openssl verify -CAfile /etc/boulder/webpki/root-rsa.cert.pem \
    /etc/boulder/webpki/int-rsa-a.cert.pem
```

### Vulnerability Scanning

```bash
# Scan container images (example with trivy)
trivy image boulder:local

# Check for exposed secrets
kubectl get secrets -n boulder -o yaml | grep -v "kubernetes.io/service-account"
```

---

This testing guide provides comprehensive procedures for validating Boulder ACME CA functionality in Kubernetes. For additional troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).