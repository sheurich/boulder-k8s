# Boulder Kubernetes Migration - Project Notes

## What Was Done

### 1. Infrastructure Setup
- **Minikube**: Installed with Docker driver (4GB RAM, 4 CPUs)
- **Storage**: Standard storage class with persistent volumes
- **Boulder Image**: Built custom image from source using `boulder.dockerfile`

### 2. Kubernetes Manifests
- **Project Structure**: Moved k8s manifests from `boulder/k8s/` to root `k8s/`
- **Key Files**: Created deployments for all services with proper configuration
- **Configuration**: Fixed volume mounts, image references, and service discovery

## Current State

### ✅ Successfully Running Services (8/10):

1. **Consul Service Mesh**: `bconsul-*` - Running
2. **MySQL Database**: `bmysql-*` - Running  
3. **Jaeger Tracing**: `bjaeger-*` - Running
4. **PKI Metal**: `bpkimetal-*` - Running
5. **Redis Cluster**: `bredis-1-*` through `bredis-4-*` - All running with dedicated PVCs

### 🔄 Services Requiring Redesign (2/10):

1. **Boulder CA**: CrashLoopBackOff - **REQUIRES MICROSERVICE ARCHITECTURE** 
2. **ProxySQL**: CrashLoopBackOff - Database connectivity issues

### Infrastructure Status:

- **Cluster**: Minikube running with 4GB RAM, 4 CPUs
- **Storage**: Redis cluster (4 instances) with dedicated 1Gi PVCs  
- **Networking**: All services have ClusterIP services for internal communication
- **Images**: Custom Boulder image available in cluster

## What Was Fixed This Session

### Redis Cluster Implementation:
- **Problem**: Redis instances 2-4 were missing
- **Solution**: Applied successful Redis-1 pattern to all instances
- **Result**: Complete 4-instance Redis cluster with persistent storage

### Key Insight Applied:
Separate PVCs prevent data conflicts in Redis clusters

### **CRITICAL ARCHITECTURE DISCOVERY**:

**Boulder is a microservices architecture** (discovered via `boulder/test/startservers.py`):

**Services Required**:
- `boulder-sa` (Storage Authority) - 2 instances  
- `boulder-ca` (Certificate Authority) - 2 instances
- `boulder-ra` (Registration Authority) - 2 instances + 2 SCT providers
- `boulder-va` (Validation Authority) - 2 instances
- `boulder-wfe2` (Web Front End)
- `nonce-service` - 3 instances
- `ocsp-responder`

**Current Issue**: Single `boulder-deployment.yaml` treats Boulder as monolithic service → CrashLoopBackOff

**Solution**: Replace with individual microservice deployments using `startservers.py` dependencies

## Next Tasks

### **IMMEDIATE PRIORITY**:

1. **Verify Redis Cluster**:
   ```bash
   kubectl get pods | grep bredis
   for i in {1..4}; do kubectl exec bredis-$i-* -- redis-cli ping; done
   ```

2. **CRITICAL: Redesign Boulder Architecture**:
   ```bash
   kubectl describe deployment boulder
   kubectl logs deployment/boulder --tail=50
   ```
   **Actions**: Replace single `boulder-deployment.yaml` with microservice deployments based on `startservers.py`
   **Order**: `boulder-sa` → `boulder-ca` → `boulder-ra` → `boulder-wfe2`

3. **Fix ProxySQL**: Create ProxySQL ConfigMap for Boulder database access

### **SECONDARY TASKS**:
4. **Service Integration Testing**: Test Boulder microservices with Redis cluster and Consul
5. **Move to Phase 4**: PKI & secrets management once Boulder microservices are deployed

### Verification Commands:

```bash
# Check Redis cluster health
for i in {1..4}; do
  kubectl exec bredis-$i-* -- redis-cli ping
done

# UPDATED: Check Boulder microservices (once redesigned)
kubectl get pods | grep boulder-
kubectl logs deployment/boulder-sa-1 --tail=20
kubectl logs deployment/boulder-ca-1 --tail=20
```

## Commands for Next Developer:

```bash
# Start the cluster
minikube start

# Check current status
kubectl get pods -o wide
kubectl get pvc

# Monitor progress
kubectl get pods -w

# Debug failing pods
kubectl logs <pod-name> --tail=50
kubectl describe pod <pod-name>
```

## Project Status Summary:

**Phase 1 & 2**: ✅ COMPLETED - Docker Compose analysis and Kubernetes manifest generation
**Phase 3**: 🔄 75% COMPLETE - Redis cluster fully implemented, MySQL running, **CRITICAL**: Boulder microservice architecture redesign required
**Phase 4**: ⏳ READY TO START - PKI and secrets management once Boulder microservices are deployed

The Redis cluster completion represents a major milestone. However, the **critical architectural discovery** that Boulder requires a microservices deployment approach means the Boulder component needs complete redesign before the migration can be considered successful. The project is positioned for rapid completion once the Boulder microservice manifests are created based on the `startservers.py` blueprint.
