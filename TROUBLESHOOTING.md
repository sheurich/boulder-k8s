# Boulder Kubernetes Troubleshooting Guide

This guide provides solutions to common issues encountered when deploying Boulder on Kubernetes.

## Quick Diagnostics

```bash
# Check cluster and pod status
make status

# Check Boulder service health
kubectl get pods -n boulder
kubectl get certificates -n boulder
kubectl get secrets -n boulder | grep tls
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

### 4. cert-manager pods not ready

**Error:**
```
cert-manager-controller    0/1     Running   0    5m
```

**Cause:** Missing RBAC permissions or leader election issues  
**Solution:**
```bash
# Apply cert-manager RBAC
kubectl apply -f k8s/cert-manager/cert-manager-rbac.yaml

# Restart cert-manager pods
kubectl delete pods -n cert-manager --all

# Wait for cert-manager to be ready
kubectl wait --for=condition=available deployment --all -n cert-manager --timeout=300s
```

### 5. Boulder service configuration errors

**Error:**
```
Error validating config file: json: unknown field "CheckCertificateBySerial"
```

**Cause:** Using deprecated Boulder configuration options  
**Solution:**
```bash
# Check for deprecated config options in Boulder configs
grep -r "CheckCertificateBySerial\|OCSPUpdater\|AkamaiPurger" k8s/config/ || echo "No deprecated options found"

# Update SA configuration to remove deprecated flags
kubectl get configmap boulder-sa-config -n boulder -o json | \
  jq 'del(.data."sa.json" | fromjson | .sa.features.CheckCertificateBySerial)' | \
  kubectl apply -f -

# Restart affected service
kubectl rollout restart deployment boulder-sa -n boulder
```

### 6. Syslog connection errors

**Error:**
```
panic: Could not connect to Syslog: Unix syslog delivery error
```

**Cause:** Boulder trying to use syslog in distroless container  
**Solution:**
```bash
# Update logging configuration to disable syslog
kubectl get configmap boulder-sa-config -n boulder -o json | \
  jq '.data."sa.json" |= (fromjson | .syslog.syslogLevel = -1 | tostring)' | \
  kubectl apply -f -

# Restart the service
kubectl rollout restart deployment boulder-sa -n boulder
```

### 7. Database connection timeouts

**Error:**
```
Error connecting to database: context deadline exceeded
```

**Cause:** Database not ready or network connectivity issues  
**Solution:**
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

### 8. Network policy blocking communication

**Error:**
```
context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

**Cause:** Network policies or firewall rules blocking pod-to-pod communication  
**Solution:**
```bash
# Check network policies
kubectl get networkpolicy -n boulder

# Test service connectivity
kubectl exec -it deployment/boulder-sa -n boulder -- \
  nc -zv boulder-ca.boulder.svc.cluster.local 9398

# Temporarily disable network policies for debugging
kubectl delete networkpolicy --all -n boulder
```

## Health Check Commands

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
2. **Use `make deploy`** which includes proper dependency ordering
3. **Monitor logs** during deployment: `kubectl logs -f deployment/boulder-sa -n boulder`
4. **Test in isolated environment** before production deployment