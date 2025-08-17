# Boulder Kubernetes Deployment Guide

This document provides comprehensive deployment instructions for Boulder ACME CA on Kubernetes, covering everything from initial setup to production deployment scenarios.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Deployment](#quick-deployment)
- [Detailed Deployment Steps](#detailed-deployment-steps)
- [Infrastructure Services](#infrastructure-services)
- [Boulder Services](#boulder-services)
- [Verification](#verification)
- [Configuration Management](#configuration-management)
- [Deployment Scenarios](#deployment-scenarios)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

## Overview

Boulder Kubernetes deployment follows a phased approach to ensure proper service dependencies and startup order. The deployment excludes all OCSP-related services as they are deprecated in Boulder.

### Deployment Phases

1. **Prerequisites** - Cluster setup and tool validation
2. **Infrastructure** - Database, cache, and proxy services
3. **Foundation** - Core Boulder services (SA, Publisher, Remote VAs)
4. **Validation** - Domain validation services (VA)
5. **Certificate** - Certificate signing services (CA, SCT Provider)
6. **Registration** - Certificate request processing (RA)
7. **Web** - Public ACME API endpoints (WFE2, Nonce Service)
8. **Verification** - Health checks and integration tests

### Service Dependency Order

```
Infrastructure → Foundation → Validation → Certificate → Registration → Web
     ↓               ↓           ↓            ↓             ↓          ↓
  MariaDB        →    SA       →    VA    →     CA       →    RA    →  WFE2
  ProxySQL           Publisher      ↑                       ↑        ↑
  Redis       →   Remote VAs    ────┘                       │        │
                                                            │        └→ Nonce Service
                                                            └→ SCT Provider
```

## Prerequisites

### Required Tools

Ensure all required tools are installed before beginning deployment:

```bash
# Quick install using Homebrew
brew bundle

# Or install individually
brew install docker kubectl kind go python3
brew install kubeconform yamllint shellcheck markdownlint-cli
```

### Tool Versions

- **Docker**: 20.10+ (container runtime)
- **kubectl**: 1.25+ (Kubernetes CLI)
- **kind**: 0.17+ (local Kubernetes)
- **Go**: 1.21+ (for integration tests)
- **Python**: 3.8+ (for test scripts)

### System Requirements

#### Minimum Resources
- **CPU**: 4 cores
- **Memory**: 8GB RAM
- **Storage**: 20GB available space
- **Network**: Internet access for external dependencies

#### Recommended Resources
- **CPU**: 8+ cores for optimal performance
- **Memory**: 16GB+ RAM for full test suite
- **Storage**: 50GB+ for logs and persistent data

### Network Requirements

The deployment requires access to:
- **Container Registries**: Docker Hub, etc.
- **Certificate Transparency Logs**: For publisher service
- **DNS Resolution**: For domain validation
- **Package Repositories**: For Boulder dependencies

## Quick Deployment

For rapid deployment, use the automated deployment script:

```bash
# Clone and initialize
git clone <repository-url>
cd boulder-k8s
git submodule update --init --recursive

# Create cluster and deploy
kind create cluster --name boulder-k8s --config kind-config.yaml
./k8s/scripts/deploy.sh

# Verify deployment
./k8s/scripts/health-check.sh
curl -s http://localhost:4001/directory | jq .
```

This performs the complete deployment process automatically. For detailed manual deployment, continue with the sections below.

## Detailed Deployment Steps

### Step 1: Environment Preparation

#### Clone Repository

```bash
git clone <repository-url>
cd boulder-k8s
```

#### Initialize Submodules

Boulder source code is included as a Git submodule:

```bash
git submodule update --init --recursive

# Verify submodule initialization
ls -la vendor/github.com/letsencrypt/boulder/
```

#### Validate Environment

```bash
# Check tool availability
make lint

# Verify Docker is running
docker version

# Check kubectl configuration
kubectl version --client
```

### Step 2: Kubernetes Cluster Setup

#### Create kind Cluster

Use the provided configuration for optimal Boulder deployment:

```bash
kind create cluster --name boulder-k8s --config kind-config.yaml
```

The kind configuration includes:
- **Port Mappings**: ACME endpoints (4001, 4431) and ingress (80, 443)
- **Multi-Node**: Control plane + 2 worker nodes for load balancing
- **Resource Allocation**: Optimized for Boulder services

#### Verify Cluster

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# Verify context
kubectl config current-context
```

#### Alternative Cluster Setup

For non-kind clusters (GKE, EKS, AKS):

```bash
# Configure kubectl for your cluster
# Example for GKE:
gcloud container clusters get-credentials boulder-cluster --zone us-central1-a

# Verify connectivity
kubectl get namespaces
```

### Step 3: Build Boulder Container Image

#### Option A: Use Existing Image

If Boulder image is available in a registry:

```bash
# Pull and load into kind
docker pull letsencrypt/boulder:latest
kind load docker-image letsencrypt/boulder:latest --name boulder-k8s
```

#### Option B: Build from Source

Build Boulder image from the included source:

```bash
# Navigate to Boulder source
cd vendor/github.com/letsencrypt/boulder

# Build container image
docker build -t boulder:local .

# Load into kind cluster
kind load docker-image boulder:local --name boulder-k8s

# Return to project root
cd ../../..
```

#### Verify Image

```bash
# Check image is available in cluster
docker exec -it boulder-k8s-control-plane crictl images | grep boulder
```

## Infrastructure Services

Infrastructure services must be deployed first as they provide foundational services for Boulder components.

### Phase 1: Namespace and RBAC

```bash
# Create Boulder namespace
kubectl apply -f k8s/namespaces/boulder-namespace.yaml

# Verify namespace creation
kubectl get namespace boulder
```

### Phase 2: Secrets

Deploy all secrets before starting services:

```bash
# Apply database credentials and certificates
kubectl apply -f k8s/secrets/

# Verify secrets (don't show values)
kubectl get secrets -n boulder
```

### Phase 3: Database Services

#### Deploy MariaDB

```bash
# Deploy MariaDB StatefulSet
kubectl apply -f k8s/deployments/infrastructure/mariadb.yaml
kubectl apply -f k8s/services/infrastructure/mariadb-service.yaml

# Wait for MariaDB to be ready
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
    statefulset/mariadb -n boulder --timeout=300s

# Verify MariaDB is running
kubectl get pods -n boulder -l app=mariadb
```

#### Deploy Redis

```bash
# Deploy Redis instances for rate limiting
kubectl apply -f k8s/deployments/infrastructure/redis.yaml
kubectl apply -f k8s/services/infrastructure/redis-service.yaml

# Wait for both Redis instances
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
    statefulset/redis-0 -n boulder --timeout=300s
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
    statefulset/redis-1 -n boulder --timeout=300s

# Verify Redis instances
kubectl get pods -n boulder -l app=redis
```

#### Deploy ProxySQL

ProxySQL provides database connection pooling:

```bash
# Deploy ProxySQL (depends on MariaDB)
kubectl apply -f k8s/deployments/infrastructure/proxysql.yaml
kubectl apply -f k8s/services/infrastructure/proxysql-service.yaml

# Wait for ProxySQL to be ready
kubectl wait --for=condition=available \
    deployment/proxysql -n boulder --timeout=300s

# Verify ProxySQL connectivity
kubectl get pods -n boulder -l app=proxysql
```

#### Verify Infrastructure

```bash
# Check all infrastructure pods are running
kubectl get pods -n boulder

# Test database connectivity
kubectl exec -n boulder deployment/proxysql -- nc -zv mariadb 3306

# Test Redis connectivity
kubectl exec -n boulder statefulset/redis-0 -- redis-cli ping
```

## Boulder Services

Boulder services are deployed in dependency order to ensure proper startup.

### Phase 4: Foundation Services

#### Deploy Storage Authority

```bash
# Deploy SA (depends on ProxySQL)
kubectl apply -f k8s/deployments/boulder/sa.yaml

# Wait for SA to be ready
kubectl wait --for=condition=available \
    deployment/boulder-sa -n boulder --timeout=300s

# Verify SA is running
kubectl get pods -n boulder -l app=boulder-sa
```

#### Deploy Publisher

```bash
# Deploy Publisher (no dependencies)
kubectl apply -f k8s/deployments/boulder/publisher.yaml

# Wait for Publisher to be ready
kubectl wait --for=condition=available \
    deployment/boulder-publisher -n boulder --timeout=300s

# Verify Publisher is running
kubectl get pods -n boulder -l app=boulder-publisher
```

#### Deploy Remote VAs

Remote VAs provide multi-perspective validation:

```bash
# Deploy Remote VA services
kubectl apply -f k8s/deployments/boulder/remote-va1.yaml
kubectl apply -f k8s/deployments/boulder/remote-va2.yaml
kubectl apply -f k8s/services/boulder/remote-va1-service.yaml
kubectl apply -f k8s/services/boulder/remote-va2-service.yaml

# Wait for Remote VAs
kubectl wait --for=condition=available \
    deployment/remote-va1 -n boulder --timeout=300s
kubectl wait --for=condition=available \
    deployment/remote-va2 -n boulder --timeout=300s

# Verify Remote VAs
kubectl get pods -n boulder -l app=remote-va
```

### Phase 5: Validation Services

#### Deploy Validation Authority

```bash
# Deploy VA (depends on SA and Remote VAs)
kubectl apply -f k8s/deployments/boulder/va.yaml

# Wait for VA to be ready
kubectl wait --for=condition=available \
    deployment/boulder-va -n boulder --timeout=300s

# Verify VA is running
kubectl get pods -n boulder -l app=boulder-va
```

### Phase 6: Certificate Services

#### Deploy SCT Provider

```bash
# Deploy SCT Provider (specialized RA for development)
kubectl apply -f k8s/deployments/boulder/sct-provider.yaml
kubectl apply -f k8s/services/boulder/sct-provider-service.yaml

# Wait for SCT Provider to be ready
kubectl wait --for=condition=available \
    deployment/boulder-sct-provider -n boulder --timeout=300s

# Verify SCT Provider is running
kubectl get pods -n boulder -l app=boulder-sct-provider
```

#### Deploy Certificate Authority

```bash
# Deploy CA (depends on SA and SCT Provider)
kubectl apply -f k8s/deployments/boulder/ca.yaml

# Wait for CA to be ready
kubectl wait --for=condition=available \
    deployment/boulder-ca -n boulder --timeout=300s

# Verify CA is running and has signing certificates
kubectl get pods -n boulder -l app=boulder-ca
kubectl exec -n boulder deployment/boulder-ca -- \
    ls -la /etc/boulder/webpki/
```

### Phase 7: Registration Services

#### Deploy Registration Authority

```bash
# Deploy RA (depends on SA, CA, VA, Publisher)
kubectl apply -f k8s/deployments/boulder/ra.yaml

# Wait for RA to be ready
kubectl wait --for=condition=available \
    deployment/boulder-ra -n boulder --timeout=300s

# Verify RA is running
kubectl get pods -n boulder -l app=boulder-ra
```

### Phase 8: Web Services

#### Deploy Nonce Service

```bash
# Deploy Nonce Service (depends on Redis)
kubectl apply -f k8s/deployments/boulder/nonce-service.yaml

# Wait for Nonce Service to be ready
kubectl wait --for=condition=available \
    deployment/nonce-service -n boulder --timeout=300s

# Verify Nonce Service is running
kubectl get pods -n boulder -l app=nonce-service
```

#### Deploy Web Front End

```bash
# Deploy WFE2 (depends on RA, SA, Nonce Service)
kubectl apply -f k8s/deployments/boulder/wfe2.yaml

# Wait for WFE2 to be ready
kubectl wait --for=condition=available \
    deployment/boulder-wfe2 -n boulder --timeout=300s

# Verify WFE2 is running
kubectl get pods -n boulder -l app=boulder-wfe2
```

## Verification

### Service Health Checks

After deployment, verify all services are healthy:

```bash
# Comprehensive health check
./k8s/scripts/health-check.sh --verbose

# Check individual service health
kubectl get pods -n boulder -o wide
kubectl get services -n boulder
```

### ACME API Verification

Test the ACME API endpoints:

```bash
# Test ACME directory
curl -s http://localhost:4001/directory | jq .

# Expected response should include:
# - newAccount, newOrder, newNonce URLs
# - revokeCert, keyChange URLs
# - meta information

# Test nonce generation
curl -I http://localhost:4001/acme/new-nonce
```

### Database Connectivity

Verify database operations:

```bash
# Test SA database connectivity
kubectl exec -n boulder deployment/boulder-sa -- \
    nc -zv proxysql 6033

# Check database schema (if accessible)
kubectl exec -n boulder statefulset/mariadb -- \
    mysql -u boulder -p<password> -e "SHOW DATABASES;"
```

### Integration Testing

Run the complete integration test suite:

```bash
# Execute integration tests
./k8s/scripts/run-integration-tests.sh

# Monitor test progress
kubectl logs -f job/boulder-integration-test -n boulder
```

## Configuration Management

### ConfigMaps

Service configurations are managed via ConfigMaps:

```bash
# View current configurations
kubectl get configmaps -n boulder

# Update a service configuration
kubectl create configmap boulder-wfe2-config \
    --from-file=wfe2.json --dry-run=client -o yaml | \
    kubectl apply -f -

# Restart service to pick up new configuration
kubectl rollout restart deployment/boulder-wfe2 -n boulder
```

### Secrets Management

Sensitive data is stored in Kubernetes Secrets:

```bash
# List secrets (without revealing values)
kubectl get secrets -n boulder

# Update database credentials
kubectl create secret generic db-credentials \
    --from-literal=sa_dburl="mysql://user:pass@proxysql:6033/boulder" \
    --dry-run=client -o yaml | kubectl apply -f -
```

### Certificate Management

PKI certificates are mounted as Secret volumes:

```bash
# Check certificate secrets
kubectl get secrets -n boulder | grep -E "(webpki|internal-pki)"

# Verify certificate mounts in CA service
kubectl exec -n boulder deployment/boulder-ca -- \
    ls -la /etc/boulder/webpki/ /etc/boulder/certs/
```

## Deployment Scenarios

### Development Environment

For local development with minimal resources:

```bash
# Use single-replica deployments
kubectl patch deployment boulder-sa -n boulder -p \
    '{"spec":{"replicas":1}}'

# Reduce resource requests
kubectl patch deployment boulder-wfe2 -n boulder -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
```

### Staging Environment

For staging with production-like setup:

```bash
# Increase replica counts
kubectl scale deployment boulder-ra --replicas=2 -n boulder
kubectl scale deployment boulder-ca --replicas=2 -n boulder

# Enable resource limits
kubectl patch deployment boulder-wfe2 -n boulder -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"limits":{"cpu":"2000m","memory":"2Gi"}}}]}}}}'
```

### Production Environment

For production deployment considerations:

1. **Use External Database**: Replace MariaDB with managed database service
2. **External Redis**: Use managed Redis service for rate limiting
3. **Load Balancers**: Configure production load balancers
4. **Monitoring**: Deploy Prometheus and Grafana
5. **Security**: Implement NetworkPolicies and PodSecurityPolicies

```bash
# Example: Use external database
kubectl delete statefulset mariadb -n boulder
kubectl create secret generic db-credentials \
    --from-literal=sa_dburl="mysql://user:pass@prod-db.example.com:3306/boulder"
```

## Rollback Procedures

### Service Rollback

Roll back individual services if issues occur:

```bash
# Check rollout history
kubectl rollout history deployment/boulder-wfe2 -n boulder

# Rollback to previous version
kubectl rollout undo deployment/boulder-wfe2 -n boulder

# Rollback to specific revision
kubectl rollout undo deployment/boulder-wfe2 --to-revision=2 -n boulder

# Check rollback status
kubectl rollout status deployment/boulder-wfe2 -n boulder
```

### Configuration Rollback

Revert configuration changes:

```bash
# Backup current configuration
kubectl get configmap boulder-wfe2-config -n boulder -o yaml > wfe2-config-backup.yaml

# Restore previous configuration
kubectl apply -f wfe2-config-previous.yaml

# Restart service to apply changes
kubectl rollout restart deployment/boulder-wfe2 -n boulder
```

### Full Environment Rollback

Complete environment restoration:

```bash
# Delete all Boulder resources
kubectl delete namespace boulder

# Restore from backup or redeploy
kubectl apply -f k8s/namespaces/boulder-namespace.yaml
./k8s/scripts/deploy.sh
```

### Database Rollback

For database schema issues:

```bash
# Access database directly
kubectl exec -it statefulset/mariadb -n boulder -- mysql -u root -p

# Run schema migration rollback
# (Specific commands depend on migration tools used)
```

## Troubleshooting

### Common Deployment Issues

#### Services Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n boulder

# Check logs
kubectl logs deployment/<service-name> -n boulder

# Check resource constraints
kubectl top pods -n boulder
```

#### Database Connection Issues

```bash
# Test database connectivity
kubectl exec -n boulder deployment/boulder-sa -- \
    nc -zv proxysql 6033

# Check ProxySQL status
kubectl logs deployment/proxysql -n boulder

# Verify database credentials
kubectl get secret db-credentials -n boulder -o yaml
```

#### Certificate Issues

```bash
# Check certificate secrets
kubectl get secrets -n boulder | grep -E "(webpki|internal)"

# Verify certificate mounts
kubectl exec -n boulder deployment/boulder-ca -- \
    ls -la /etc/boulder/webpki/

# Check certificate validity
kubectl exec -n boulder deployment/boulder-ca -- \
    openssl x509 -in /etc/boulder/webpki/int-rsa-a.cert.pem -text -noout
```

### Performance Issues

#### Resource Constraints

```bash
# Check resource usage
kubectl top pods -n boulder
kubectl top nodes

# Increase resource limits
kubectl patch deployment boulder-wfe2 -n boulder -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"limits":{"cpu":"4000m","memory":"4Gi"}}}]}}}}'
```

#### Service Scaling

```bash
# Scale up services under load
kubectl scale deployment boulder-wfe2 --replicas=3 -n boulder
kubectl scale deployment boulder-ra --replicas=4 -n boulder

# Monitor scaling progress
kubectl get pods -n boulder -w
```

### Network Issues

#### Service Discovery

```bash
# Test internal DNS resolution
kubectl exec -n boulder deployment/boulder-wfe2 -- \
    nslookup boulder-ra.boulder.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n boulder
```

#### External Access

```bash
# Check ingress configuration
kubectl get ingress -n boulder

# Test external connectivity
curl -v http://localhost:4001/directory
```

For additional troubleshooting guidance, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

This deployment guide provides comprehensive instructions for deploying Boulder ACME CA on Kubernetes. For specific issues or advanced configurations, refer to the architecture documentation and troubleshooting guides.