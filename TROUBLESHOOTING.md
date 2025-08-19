# Boulder Kubernetes Troubleshooting Guide

This comprehensive guide provides solutions to common issues encountered when deploying Boulder on Kubernetes, from quick diagnostics to advanced troubleshooting procedures.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Service Startup Problems](#service-startup-problems)
- [Database Connectivity Issues](#database-connectivity-issues)
- [Certificate and Secret Issues](#certificate-and-secret-issues)
- [Network and DNS Problems](#network-and-dns-problems)
- [Resource Constraints](#resource-constraints)
- [ACME API Issues](#acme-api-issues)
- [Integration Test Failures](#integration-test-failures)
- [Advanced Diagnostics](#advanced-diagnostics)
- [Recovery Procedures](#recovery-procedures)
- [Performance Issues](#performance-issues)

## Quick Diagnostics

Start with these quick commands to assess system status:

```bash
# Check cluster and pod status
kubectl cluster-info
kubectl get pods -n boulder
kubectl get certificates -n boulder
kubectl get secrets -n boulder | grep tls

# Run health check
./k8s/scripts/health-check.sh --verbose

# Check resource usage
kubectl top pods -n boulder
kubectl top nodes
```

### Common Issue Indicators

```bash
# Check for pods in error states
kubectl get pods -n boulder | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)"

# Check recent events
kubectl get events -n boulder --sort-by='.lastTimestamp' | tail -20

# Check service endpoints
kubectl get endpoints -n boulder

# Check persistent volumes
kubectl get pv,pvc -n boulder
```

## Common Issues and Solutions

### 1. ImagePullBackOff on `boulder:latest`

**Error:**
```
Failed to pull image "docker.io/library/boulder:latest": failed to pull and unpack image
```

**Cause:** Boulder image not built or loaded into cluster  
**Solution:**
```bash
# Build Boulder image
make docker-build

# Load image into kind cluster  
kind load docker-image boulder-k8s:latest --name boulder-k8s

# Restart affected pods
kubectl rollout restart deployment -n boulder --selector="app!=mariadb,app!=redis,app!=proxysql"
```

### 2. MountVolume.SetUp failed: secret not found

**Error:**
```
MountVolume.SetUp failed for volume "server-tls" : secret "boulder-sa-grpc-tls" not found
```

**Cause:** cert-manager not deployed or certificates not issued  
**Solution:**
```bash
# Deploy cert-manager and certificates
./k8s/scripts/setup-tls.sh

# Wait for certificates to be ready
kubectl wait --for=condition=Ready certificate --all -n boulder --timeout=300s

# Restart Boulder services after certificates are ready
kubectl rollout restart deployment -n boulder --selector="app.kubernetes.io/part-of=boulder"
```

### 3. ProxySQL Error: Access denied for user 'boulder'

**Error:**
```
[AUDIT] While initializing dbMap: Error 1045 (28000): ProxySQL Error: Access denied for user 'boulder'@'IP' (using password: YES)
```

**Cause:** Database credentials mismatch or ProxySQL configuration issue  
**Solution:**
```bash
# Check database credentials
kubectl get secret db-credentials -n boulder -o yaml

# Check ProxySQL logs
kubectl logs -l app=proxysql -n boulder

# Verify ProxySQL configuration
kubectl get configmap proxysql-config -n boulder -o yaml

# If credentials are wrong, update them and restart ProxySQL
kubectl rollout restart deployment proxysql -n boulder
```

### 4. Boulder service configuration errors

**Error:**
```
Error validating config file: json: unknown field "CheckCertificateBySerial"
```

**Cause:** Using deprecated Boulder configuration options  
**Solution:**
```bash
# Check for deprecated config options in Boulder configs
grep -r "CheckCertificateBySerial\|OCSPUpdater\|AkamaiPurger" k8s/configmaps/ || echo "No deprecated options found"

# Update SA configuration to remove deprecated flags
kubectl get configmap boulder-sa-config -n boulder -o json | \
  jq 'del(.data."sa.json" | fromjson | .sa.features.CheckCertificateBySerial)' | \
  kubectl apply -f -

# Restart affected service
kubectl rollout restart deployment boulder-sa -n boulder
```

## Service Startup Problems

### Issue: Cannot Connect to Kubernetes Cluster

**Symptoms:**
- `kubectl` commands fail with connection errors
- `The connection to the server localhost:8080 was refused`
- `Unable to connect to the server: dial tcp: lookup`

**Solutions:**

**For kind clusters:**
```bash
# Verify kind cluster exists
kind get clusters

# Get kubeconfig for kind cluster
kind get kubeconfig --name boulder-k8s

# Set correct context
kubectl config use-context kind-boulder-k8s
```

### Issue: Pods Stuck in Init or Pending State

**Diagnosis:**
```bash
# Check pod status and events
kubectl describe pod <pod-name> -n boulder

# Check init container logs
kubectl logs <pod-name> -n boulder -c <init-container-name>

# Check service dependencies
kubectl get pods -n boulder | grep -E "(mariadb|redis|proxysql)"
```

**Solutions:**
```bash
# Ensure infrastructure services are running first
kubectl get pods -n boulder -l app=mariadb
kubectl get pods -n boulder -l app=redis
kubectl get pods -n boulder -l app=proxysql

# Test DNS resolution from failing pod
kubectl exec -n boulder <pod-name> -- nslookup boulder-sa.boulder.svc.cluster.local
```

## Database Connectivity Issues

### Issue: MariaDB Not Starting

**Diagnosis:**
```bash
# Check MariaDB pod status
kubectl get pods -n boulder -l app=mariadb

# Check MariaDB logs
kubectl logs statefulset/mariadb -n boulder

# Check persistent volume claims
kubectl get pvc -n boulder
```

**Solutions:**
```bash
# Check database initialization
kubectl exec -n boulder statefulset/mariadb -- mysql -u root -p -e "SHOW DATABASES;"

# Reset database if needed (WARNING: destroys data)
kubectl delete statefulset mariadb -n boulder
kubectl delete pvc mariadb-data -n boulder
kubectl apply -f k8s/deployments/infrastructure/mariadb.yaml
```

### Issue: Database connection timeouts

**Error:**
```
Error connecting to database: context deadline exceeded
```

**Solutions:**
```bash
# Check database pod status
kubectl get pods -l app=mariadb -n boulder

# Test database connectivity
kubectl exec -it mariadb-0 -n boulder -- mysql -u root -p -e "SELECT 1"

# Check ProxySQL status
kubectl logs -l app=proxysql -n boulder --tail=50

# Restart database connection chain
kubectl rollout restart deployment proxysql -n boulder
kubectl rollout restart statefulset mariadb -n boulder
```

## Certificate and Secret Issues

### Issue: Missing or Invalid Certificates

**Diagnosis:**
```bash
# Check certificate secrets
kubectl get secrets -n boulder | grep -E "(webpki|internal|cert)"

# Verify certificate mounts
kubectl exec -n boulder deployment/boulder-ca -- \
  ls -la /etc/boulder/webpki/ /etc/boulder/certs/

# Check certificate validity
kubectl exec -n boulder deployment/boulder-ca -- \
  openssl x509 -in /etc/boulder/webpki/int-rsa-a.cert.pem -text -noout
```

**Solutions:**
```bash
# Regenerate certificates
./k8s/scripts/generate-webpki-certs.sh

# Restart services
kubectl rollout restart deployment/boulder-ca -n boulder
```

### Issue: cert-manager pods not ready

**Solutions:**
```bash
# Apply cert-manager RBAC
kubectl apply -f k8s/cert-manager/cert-manager-rbac.yaml

# Restart cert-manager pods
kubectl delete pods -n cert-manager --all

# Wait for cert-manager to be ready
kubectl wait --for=condition=available deployment --all -n cert-manager --timeout=300s
```

## Network and DNS Problems

### Issue: Service Discovery Not Working

**Diagnosis:**
```bash
# Test DNS resolution
kubectl exec -n boulder deployment/boulder-wfe2 -- \
  nslookup boulder-ra.boulder.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n boulder

# Test service connectivity
kubectl exec -n boulder deployment/boulder-wfe2 -- nc -zv boulder-ra 9394
```

**Solutions:**
```bash
# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Restart CoreDNS if needed
kubectl rollout restart deployment/coredns -n kube-system
```

### Issue: Network policy blocking communication

**Error:**
```
context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

**Solutions:**
```bash
# Check network policies
kubectl get networkpolicy -n boulder

# Test service connectivity
kubectl exec -it deployment/boulder-sa -n boulder -- \
  nc -zv boulder-ca.boulder.svc.cluster.local 9393

# Temporarily disable network policies for debugging
kubectl delete networkpolicy --all -n boulder
```

## Resource Constraints

### Issue: Out of Memory (OOMKilled)

**Diagnosis:**
```bash
# Check for OOMKilled events
kubectl get events -n boulder | grep OOMKilled

# Check resource usage
kubectl top pods -n boulder --sort-by=memory
```

**Solutions:**
```bash
# Increase memory limits
kubectl patch deployment boulder-wfe2 -n boulder -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"limits":{"memory":"2Gi"}}}]}}}}'

# Reduce replica counts
kubectl scale deployment boulder-ra --replicas=1 -n boulder
```

## ACME API Issues

### Issue: ACME Directory Not Accessible

**Diagnosis:**
```bash
# Test directory endpoint
curl -s http://localhost:4001/directory

# Check WFE2 service status
kubectl get pods -n boulder -l app=boulder-wfe2

# Check WFE2 logs
kubectl logs deployment/boulder-wfe2 -n boulder
```

**Solutions:**
```bash
# Port forwarding for local access
kubectl port-forward service/boulder-wfe2 4001:4001 -n boulder

# Test forwarded port
curl -s http://localhost:4001/directory
```

### Issue: Certificate Issuance Failures

**Diagnosis:**
```bash
# Check CA service logs
kubectl logs deployment/boulder-ca -n boulder

# Check RA service logs
kubectl logs deployment/boulder-ra -n boulder

# Test certificate signing manually
kubectl exec -n boulder deployment/boulder-ca -- \
  ls -la /etc/boulder/webpki/
```

## Integration Test Failures

### Issue: Integration Tests Timeout

**Diagnosis:**
```bash
# Check test job status
kubectl get job boulder-integration-test -n boulder

# Monitor test progress
kubectl logs -f job/boulder-integration-test -n boulder
```

**Solutions:**
```bash
# Run with longer timeout
./k8s/scripts/run-integration-tests.sh --timeout 3600s

# Check service health during tests
./k8s/scripts/health-check.sh --verbose
```

## Advanced Diagnostics

### Service Health Endpoints

```bash
# Check Boulder service health endpoints
for service in sa ca ra va wfe2; do
  echo "Checking boulder-$service health..."
  kubectl exec deployment/boulder-$service -n boulder -- \
    curl -sf http://localhost:8003/debug/health || echo "Failed"
done
```

### Certificate Status

```bash
# Check all certificate status
kubectl get certificates -n boulder -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,REASON:.status.conditions[0].reason

# Describe failed certificates
kubectl get certificates -n boulder -o json | \
  jq -r '.items[] | select(.status.conditions[]?.status != "True") | .metadata.name' | \
  xargs -I {} kubectl describe certificate {} -n boulder
```

### Database Connectivity

```bash
# Test database connectivity from Boulder pods
kubectl exec deployment/boulder-sa -n boulder -- \
  nc -zv mariadb.boulder.svc.cluster.local 3306

kubectl exec deployment/boulder-sa -n boulder -- \
  nc -zv proxysql.boulder.svc.cluster.local 6033
```

## Recovery Procedures

### Service Recovery

```bash
# Restart all Boulder services
kubectl rollout restart deployment/boulder-wfe2 -n boulder
kubectl rollout restart deployment/boulder-ra -n boulder
kubectl rollout restart deployment/boulder-sa -n boulder
kubectl rollout restart deployment/boulder-ca -n boulder
kubectl rollout restart deployment/boulder-va -n boulder
kubectl rollout restart deployment/boulder-publisher -n boulder

# Wait for services to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/boulder-wfe2 deployment/boulder-ra deployment/boulder-sa \
  deployment/boulder-ca deployment/boulder-va deployment/boulder-publisher \
  -n boulder
```

### Complete Environment Reset

```bash
# Full environment cleanup and redeploy
kubectl delete namespace boulder
kubectl apply -f k8s/namespaces/boulder-namespace.yaml
./k8s/scripts/deploy.sh
```

## Performance Issues

### Resource Optimization

```bash
# Optimize database connections
kubectl patch configmap boulder-sa-config -n boulder --type merge -p \
  '{"data":{"maxOpenConns":"100","maxIdleConns":"50","connMaxLifetime":"5m"}}'

# Scale high-traffic services
kubectl scale deployment boulder-wfe2 --replicas=3 -n boulder

# Enable horizontal pod autoscaling
kubectl autoscale deployment boulder-wfe2 --cpu-percent=70 --min=2 --max=10 -n boulder
```

## Getting Help

If these solutions don't resolve your issue:

1. **Check logs**: `kubectl logs -l app=<service-name> -n boulder --tail=100`
2. **Describe resources**: `kubectl describe pod <pod-name> -n boulder`
3. **Check events**: `kubectl get events -n boulder --sort-by='.lastTimestamp'`
4. **Review configuration**: Compare with working upstream Boulder configs
5. **Verify prerequisites**: Ensure all required tools and permissions are available

## Prevention

To avoid these issues:

1. **Always run `make lint`** before deployment
2. **Use deployment scripts** which include proper dependency ordering
3. **Monitor logs** during deployment: `kubectl logs -f deployment/boulder-sa -n boulder`
4. **Test in isolated environment** before production deployment

---

For additional troubleshooting context, consult:
- [`reference/SPECp1.md`](reference/SPECp1.md) - Phase 1 specification
- [`architecture/phase1.md`](architecture/phase1.md) - Architecture overview
- [`architecture/shared/service-matrix.md`](architecture/shared/service-matrix.md) - Service specifications