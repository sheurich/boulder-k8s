# Boulder Kubernetes Troubleshooting Guide

This document provides comprehensive troubleshooting guidance for Boulder ACME CA deployed on Kubernetes, covering common issues, diagnostic procedures, and resolution steps.

## Table of Contents

- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [Cluster and Environment Issues](#cluster-and-environment-issues)
- [Service Startup Problems](#service-startup-problems)
- [Database Connectivity Issues](#database-connectivity-issues)
- [Redis Connection Problems](#redis-connection-problems)
- [Certificate and Secret Issues](#certificate-and-secret-issues)
- [Network and DNS Problems](#network-and-dns-problems)
- [Resource Constraints](#resource-constraints)
- [ACME API Issues](#acme-api-issues)
- [Integration Test Failures](#integration-test-failures)
- [Log Analysis](#log-analysis)
- [Recovery Procedures](#recovery-procedures)
- [Performance Issues](#performance-issues)

## Quick Diagnostic Commands

Before diving into specific issues, run these quick diagnostic commands to gather essential information:

### System Status Check

```bash
# Check cluster connectivity
kubectl cluster-info
kubectl get nodes

# Check Boulder namespace and resources
kubectl get all -n boulder

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

## Cluster and Environment Issues

### Issue: Cannot Connect to Kubernetes Cluster

#### Symptoms
- `kubectl` commands fail with connection errors
- `The connection to the server localhost:8080 was refused`
- `Unable to connect to the server: dial tcp: lookup`

#### Diagnosis
```bash
# Check current context
kubectl config current-context

# List available contexts
kubectl config get-contexts

# Check cluster info
kubectl cluster-info
```

#### Solutions

**For kind clusters:**
```bash
# Verify kind cluster exists
kind get clusters

# Get kubeconfig for kind cluster
kind get kubeconfig --name boulder-k8s

# Set correct context
kubectl config use-context kind-boulder-k8s
```

**For cloud clusters (GKE, EKS, AKS):**
```bash
# GKE example
gcloud container clusters get-credentials boulder-cluster --zone us-central1-a

# EKS example
aws eks update-kubeconfig --region us-west-2 --name boulder-cluster

# AKS example
az aks get-credentials --resource-group myResourceGroup --name boulder-cluster
```

**For general kubeconfig issues:**
```bash
# Check kubeconfig file
ls -la ~/.kube/config

# Validate kubeconfig syntax
kubectl config view

# Test with explicit kubeconfig
kubectl --kubeconfig=/path/to/config cluster-info
```

### Issue: Insufficient Cluster Resources

#### Symptoms
- Pods stuck in `Pending` state
- Events show `Insufficient memory` or `Insufficient cpu`
- Nodes show high resource usage

#### Diagnosis
```bash
# Check node resources
kubectl describe nodes

# Check resource requests and limits
kubectl describe pods -n boulder | grep -A 5 -B 5 "Requests\|Limits"

# Check resource usage
kubectl top nodes
kubectl top pods -n boulder
```

#### Solutions

**Scale cluster resources:**
```bash
# For kind - recreate with more resources
kind delete cluster --name boulder-k8s
kind create cluster --name boulder-k8s --config kind-config.yaml

# For cloud clusters - add nodes or resize
# GKE example:
gcloud container clusters resize boulder-cluster --num-nodes=4 --zone=us-central1-a
```

**Reduce resource requirements:**
```bash
# Reduce replica counts
kubectl scale deployment boulder-ra --replicas=1 -n boulder
kubectl scale deployment boulder-ca --replicas=1 -n boulder

# Reduce resource requests
kubectl patch deployment boulder-wfe2 -n boulder -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
```

## Service Startup Problems

### Issue: Pods Stuck in Init or Pending State

#### Symptoms
- Pods remain in `Init:0/1` or `Pending` state
- Services don't become ready
- Health checks fail

#### Diagnosis
```bash
# Check pod status and events
kubectl describe pod <pod-name> -n boulder

# Check init container logs
kubectl logs <pod-name> -n boulder -c <init-container-name>

# Check service dependencies
kubectl get pods -n boulder | grep -E "(mariadb|redis|proxysql)"
```

#### Solutions

**Dependency issues:**
```bash
# Ensure infrastructure services are running first
kubectl get pods -n boulder -l app=mariadb
kubectl get pods -n boulder -l app=redis
kubectl get pods -n boulder -l app=proxysql

# If infrastructure isn't ready, wait or troubleshoot those services first
kubectl wait --for=condition=available deployment/proxysql -n boulder --timeout=300s
```

**Service discovery issues:**
```bash
# Test DNS resolution from failing pod
kubectl exec -n boulder <pod-name> -- nslookup boulder-sa.boulder.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n boulder
```

### Issue: Services Crashing on Startup

#### Symptoms
- Pods in `CrashLoopBackOff` state
- Services restart repeatedly
- Readiness probes fail

#### Diagnosis
```bash
# Check current and previous logs
kubectl logs <pod-name> -n boulder
kubectl logs <pod-name> -n boulder --previous

# Check resource limits
kubectl describe pod <pod-name> -n boulder | grep -A 10 "Limits\|Requests"

# Check configuration mounts
kubectl exec -n boulder <pod-name> -- ls -la /etc/boulder/
```

#### Solutions

**Configuration issues:**
```bash
# Verify configmaps exist
kubectl get configmaps -n boulder

# Check configuration content
kubectl get configmap boulder-wfe2-config -n boulder -o yaml

# Recreate configuration if needed
kubectl delete configmap boulder-wfe2-config -n boulder
kubectl create configmap boulder-wfe2-config --from-file=wfe2.json -n boulder
```

**Resource issues:**
```bash
# Increase memory limits
kubectl patch deployment boulder-wfe2 -n boulder -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"limits":{"memory":"2Gi"}}}]}}}}'

# Check for OOMKilled events
kubectl get events -n boulder | grep OOMKilled
```

## Database Connectivity Issues

### Issue: MariaDB Not Starting

#### Symptoms
- MariaDB pod in `CrashLoopBackOff` or `Error` state
- Storage Authority cannot connect to database
- ProxySQL fails to connect to MariaDB

#### Diagnosis
```bash
# Check MariaDB pod status
kubectl get pods -n boulder -l app=mariadb

# Check MariaDB logs
kubectl logs statefulset/mariadb -n boulder

# Check persistent volume claims
kubectl get pvc -n boulder

# Check storage class
kubectl get storageclass
```

#### Solutions

**Storage issues:**
```bash
# Check if PVC is bound
kubectl get pvc -n boulder

# If storage class issues, try default storage class
kubectl patch pvc mariadb-data -n boulder -p \
  '{"spec":{"storageClassName":"standard"}}'

# For kind clusters, ensure storage is available
docker exec boulder-k8s-control-plane df -h
```

**Configuration issues:**
```bash
# Check database initialization
kubectl exec -n boulder statefulset/mariadb -- mysql -u root -p -e "SHOW DATABASES;"

# Reset database if needed (WARNING: destroys data)
kubectl delete statefulset mariadb -n boulder
kubectl delete pvc mariadb-data -n boulder
kubectl apply -f k8s/deployments/infrastructure/mariadb.yaml
```

**Permission issues:**
```bash
# Check database credentials
kubectl get secret db-credentials -n boulder -o yaml

# Verify database user permissions
kubectl exec -n boulder statefulset/mariadb -- \
  mysql -u root -p -e "SELECT User, Host FROM mysql.user WHERE User='boulder';"
```

### Issue: ProxySQL Connection Problems

#### Symptoms
- Storage Authority cannot connect to ProxySQL
- Connection refused errors on port 6033
- ProxySQL pod healthy but not accessible

#### Diagnosis
```bash
# Check ProxySQL status
kubectl get pods -n boulder -l app=proxysql

# Check ProxySQL logs
kubectl logs deployment/proxysql -n boulder

# Test ProxySQL connectivity
kubectl exec -n boulder deployment/proxysql -- nc -zv localhost 6033

# Check ProxySQL configuration
kubectl exec -n boulder deployment/proxysql -- \
  mysql -u admin -padmin -h 127.0.0.1 -P6032 -e "SELECT * FROM mysql_servers;"
```

#### Solutions

**Configuration issues:**
```bash
# Check ProxySQL config
kubectl get configmap proxysql-config -n boulder -o yaml

# Restart ProxySQL
kubectl rollout restart deployment/proxysql -n boulder

# Test backend connectivity
kubectl exec -n boulder deployment/proxysql -- nc -zv mariadb 3306
```

**Service discovery issues:**
```bash
# Check service endpoints
kubectl get endpoints proxysql -n boulder

# Test service resolution
kubectl exec -n boulder deployment/boulder-sa -- \
  nslookup proxysql.boulder.svc.cluster.local
```

### Issue: Database Schema Issues

#### Symptoms
- SA service logs show schema errors
- Tables missing or have wrong structure
- Migration failures

#### Diagnosis
```bash
# Check database schema
kubectl exec -n boulder statefulset/mariadb -- \
  mysql -u boulder -p boulder -e "SHOW TABLES;"

# Check for migration logs
kubectl logs deployment/boulder-sa -n boulder | grep -i migration

# Verify database connectivity
kubectl exec -n boulder deployment/boulder-sa -- nc -zv proxysql 6033
```

#### Solutions

**Schema recreation:**
```bash
# Access database directly
kubectl exec -it statefulset/mariadb -n boulder -- mysql -u root -p

# Run schema setup (from Boulder source)
kubectl exec -n boulder deployment/boulder-sa -- \
  /go/bin/boulder-sa --config /etc/boulder/sa.json --setup-db
```

## Redis Connection Problems

### Issue: Redis Instances Not Starting

#### Symptoms
- Redis pods in error state
- Nonce service cannot connect to Redis
- Rate limiting not working

#### Diagnosis
```bash
# Check Redis pod status
kubectl get pods -n boulder -l app=redis

# Check Redis logs
kubectl logs statefulset/redis-0 -n boulder
kubectl logs statefulset/redis-1 -n boulder

# Check Redis configuration
kubectl get configmap redis-config -n boulder -o yaml
```

#### Solutions

**Configuration issues:**
```bash
# Test Redis connectivity
kubectl exec -n boulder statefulset/redis-0 -- redis-cli ping

# Check Redis authentication
kubectl exec -n boulder statefulset/redis-0 -- \
  redis-cli -a "${REDIS_PASSWORD}" ping

# Reset Redis data if needed
kubectl delete statefulset redis-0 redis-1 -n boulder
kubectl delete pvc redis-data-redis-0 redis-data-redis-1 -n boulder
kubectl apply -f k8s/deployments/infrastructure/redis.yaml
```

**Persistence issues:**
```bash
# Check PVC status
kubectl get pvc -n boulder | grep redis

# Check storage availability
kubectl describe pvc redis-data-redis-0 -n boulder
```

### Issue: Services Cannot Connect to Redis

#### Symptoms
- Nonce service shows Redis connection errors
- Rate limiting not functioning
- Authentication failures

#### Diagnosis
```bash
# Check Redis password secret
kubectl get secret redis-password -n boulder -o yaml

# Test connection from service
kubectl exec -n boulder deployment/nonce-service -- \
  nc -zv redis-0 6379

# Check Redis authentication
kubectl exec -n boulder statefulset/redis-0 -- \
  redis-cli -a "$(kubectl get secret redis-password -n boulder -o jsonpath='{.data.password}' | base64 -d)" ping
```

#### Solutions

**Authentication issues:**
```bash
# Update Redis password
kubectl create secret generic redis-password \
  --from-literal=password="newpassword" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart services that use Redis
kubectl rollout restart deployment/nonce-service -n boulder
```

## Certificate and Secret Issues

### Issue: Missing or Invalid Certificates

#### Symptoms
- CA service cannot start
- Certificate signing fails
- mTLS authentication errors between services

#### Diagnosis
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

#### Solutions

**Regenerate certificates:**
```bash
# Delete existing certificate secrets
kubectl delete secret webpki-certs internal-pki -n boulder

# Regenerate using Boulder's certificate generation
cd vendor/github.com/letsencrypt/boulder
./test/certs/generate.sh

# Create new secrets with generated certificates
kubectl create secret generic webpki-certs \
  --from-file=test/certs/webpki/ -n boulder
kubectl create secret generic internal-pki \
  --from-file=test/certs/internal/ -n boulder

# Restart services
kubectl rollout restart deployment/boulder-ca -n boulder
```

**Certificate validation:**
```bash
# Verify certificate chain
kubectl exec -n boulder deployment/boulder-ca -- \
  openssl verify -CAfile /etc/boulder/webpki/root-rsa.cert.pem \
  /etc/boulder/webpki/int-rsa-a.cert.pem

# Check certificate expiration
kubectl exec -n boulder deployment/boulder-ca -- \
  openssl x509 -in /etc/boulder/webpki/int-rsa-a.cert.pem -enddate -noout
```

### Issue: Secret Access Problems

#### Symptoms
- Pods cannot access secrets
- Permission denied errors
- Environment variables not set

#### Diagnosis
```bash
# Check secret existence
kubectl get secrets -n boulder

# Check secret permissions
kubectl describe secret db-credentials -n boulder

# Check service account permissions
kubectl get serviceaccount -n boulder
kubectl describe rolebinding -n boulder
```

#### Solutions

**Permission issues:**
```bash
# Create service account with proper permissions
kubectl create serviceaccount boulder-service -n boulder

# Create role and rolebinding
kubectl create role boulder-role --verb=get,list,watch \
  --resource=secrets,configmaps -n boulder
kubectl create rolebinding boulder-binding --role=boulder-role \
  --serviceaccount=boulder:boulder-service -n boulder

# Update deployment to use service account
kubectl patch deployment boulder-wfe2 -n boulder -p \
  '{"spec":{"template":{"spec":{"serviceAccountName":"boulder-service"}}}}'
```

## Network and DNS Problems

### Issue: Service Discovery Not Working

#### Symptoms
- Services cannot find each other
- DNS resolution failures
- Connection refused errors

#### Diagnosis
```bash
# Test DNS resolution
kubectl exec -n boulder deployment/boulder-wfe2 -- \
  nslookup boulder-ra.boulder.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n boulder

# Check DNS configuration
kubectl exec -n boulder deployment/boulder-wfe2 -- cat /etc/resolv.conf

# Test service connectivity
kubectl exec -n boulder deployment/boulder-wfe2 -- nc -zv boulder-ra 9394
```

#### Solutions

**DNS issues:**
```bash
# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS from different namespace
kubectl run test-dns --image=busybox --rm -it -- \
  nslookup boulder-wfe2.boulder.svc.cluster.local

# Restart CoreDNS if needed
kubectl rollout restart deployment/coredns -n kube-system
```

**Service configuration:**
```bash
# Check service configuration
kubectl get services -n boulder -o wide

# Verify service selectors match pod labels
kubectl describe service boulder-ra -n boulder
kubectl get pods -n boulder -l app=boulder-ra --show-labels
```

### Issue: External Access Problems

#### Symptoms
- Cannot access ACME API from outside cluster
- LoadBalancer IP not assigned
- Ingress not working

#### Diagnosis
```bash
# Check service type and external access
kubectl get services -n boulder

# For LoadBalancer services
kubectl describe service boulder-wfe2 -n boulder

# For ingress
kubectl get ingress -n boulder
kubectl describe ingress boulder-ingress -n boulder

# Test from within cluster
kubectl exec -n boulder deployment/boulder-wfe2 -- \
  curl -s http://localhost:4001/directory
```

#### Solutions

**LoadBalancer issues:**
```bash
# For kind clusters, use port forwarding
kubectl port-forward service/boulder-wfe2 4001:4001 -n boulder

# Or use NodePort
kubectl patch service boulder-wfe2 -n boulder -p \
  '{"spec":{"type":"NodePort"}}'

# Get NodePort
kubectl get service boulder-wfe2 -n boulder
```

**Ingress issues:**
```bash
# Install ingress controller (for kind)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for ingress controller
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

## Resource Constraints

### Issue: Out of Memory (OOMKilled)

#### Symptoms
- Pods restarting frequently
- `OOMKilled` in pod events
- Services becoming unresponsive

#### Diagnosis
```bash
# Check for OOMKilled events
kubectl get events -n boulder | grep OOMKilled

# Check resource usage
kubectl top pods -n boulder --sort-by=memory

# Check memory limits
kubectl describe pods -n boulder | grep -A 5 -B 5 "Limits\|Requests"
```

#### Solutions

**Increase memory limits:**
```bash
# Increase memory for specific service
kubectl patch deployment boulder-wfe2 -n boulder -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"limits":{"memory":"2Gi"}}}]}}}}'

# Increase for all Boulder services
for service in wfe2 ra sa ca va publisher; do
  kubectl patch deployment boulder-$service -n boulder -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-'$service'","resources":{"limits":{"memory":"1Gi"}}}]}}}}'
done
```

**Optimize memory usage:**
```bash
# Reduce replica counts
kubectl scale deployment boulder-ra --replicas=1 -n boulder

# Tune database connections
kubectl patch configmap boulder-sa-config -n boulder --type merge -p \
  '{"data":{"sa.json":"{\"maxOpenConns\":50,\"maxIdleConns\":25}"}}'
```

### Issue: CPU Throttling

#### Symptoms
- Slow response times
- High CPU utilization
- Request timeouts

#### Diagnosis
```bash
# Check CPU usage
kubectl top pods -n boulder --sort-by=cpu

# Check CPU limits
kubectl describe pods -n boulder | grep -A 5 -B 5 "Limits\|Requests"

# Monitor CPU throttling
kubectl exec -n boulder deployment/boulder-wfe2 -- \
  cat /sys/fs/cgroup/cpu/cpu.stat
```

#### Solutions

**Increase CPU limits:**
```bash
# Increase CPU for high-traffic services
kubectl patch deployment boulder-wfe2 -n boulder -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-wfe2","resources":{"limits":{"cpu":"2000m"}}}]}}}}'

# Scale horizontally
kubectl scale deployment boulder-wfe2 --replicas=3 -n boulder
```

## ACME API Issues

### Issue: ACME Directory Not Accessible

#### Symptoms
- ACME clients cannot connect
- Directory endpoint returns errors
- Certificate issuance fails

#### Diagnosis
```bash
# Test directory endpoint
curl -s http://localhost:4001/directory

# Check WFE2 service status
kubectl get pods -n boulder -l app=boulder-wfe2

# Check WFE2 logs
kubectl logs deployment/boulder-wfe2 -n boulder

# Test from within cluster
kubectl exec -n boulder deployment/boulder-wfe2 -- \
  curl -s http://localhost:4001/directory
```

#### Solutions

**Service issues:**
```bash
# Restart WFE2 service
kubectl rollout restart deployment/boulder-wfe2 -n boulder

# Check service dependencies
kubectl get pods -n boulder -l app=boulder-ra
kubectl get pods -n boulder -l app=boulder-sa

# Verify configuration
kubectl get configmap boulder-wfe2-config -n boulder -o yaml
```

**Port forwarding for local access:**
```bash
# Forward ACME port
kubectl port-forward service/boulder-wfe2 4001:4001 -n boulder

# Test forwarded port
curl -s http://localhost:4001/directory
```

### Issue: Certificate Issuance Failures

#### Symptoms
- ACME clients fail to get certificates
- Challenge validation fails
- CA service errors

#### Diagnosis
```bash
# Check CA service logs
kubectl logs deployment/boulder-ca -n boulder

# Check RA service logs
kubectl logs deployment/boulder-ra -n boulder

# Check VA service logs
kubectl logs deployment/boulder-va -n boulder

# Test certificate signing manually
kubectl exec -n boulder deployment/boulder-ca -- \
  ls -la /etc/boulder/webpki/
```

#### Solutions

**Certificate authority issues:**
```bash
# Verify CA has signing certificates
kubectl exec -n boulder deployment/boulder-ca -- \
  openssl x509 -in /etc/boulder/webpki/int-rsa-a.cert.pem -text -noout

# Check CA configuration
kubectl get configmap boulder-ca-config -n boulder -o yaml

# Restart CA service
kubectl rollout restart deployment/boulder-ca -n boulder
```

## Integration Test Failures

### Issue: Integration Tests Timeout

#### Symptoms
- Integration test job doesn't complete
- Tests hang on specific scenarios
- Timeout errors in test logs

#### Diagnosis
```bash
# Check test job status
kubectl get job boulder-integration-test -n boulder

# Check test pod logs
kubectl logs job/boulder-integration-test -n boulder

# Monitor test progress
kubectl logs -f job/boulder-integration-test -n boulder
```

#### Solutions

**Increase timeout:**
```bash
# Run with longer timeout
./k8s/scripts/run-integration-tests.sh --timeout 3600s

# Check resource constraints during tests
kubectl top pods -n boulder
```

**Debug specific test failures:**
```bash
# Get detailed test logs
kubectl logs job/boulder-integration-test -n boulder > test-logs.txt

# Search for specific errors
grep -i "error\|failed\|timeout" test-logs.txt

# Check service health during tests
./k8s/scripts/health-check.sh --verbose
```

### Issue: Challenge Validation Failures

#### Symptoms
- HTTP-01 challenges fail
- DNS-01 challenges timeout
- Multi-perspective validation errors

#### Diagnosis
```bash
# Check VA service logs
kubectl logs deployment/boulder-va -n boulder

# Check Remote VA connectivity
kubectl exec -n boulder deployment/boulder-va -- nc -zv remote-va1 9397

# Test DNS resolution
kubectl exec -n boulder deployment/boulder-va -- nslookup google.com
```

#### Solutions

**Network connectivity:**
```bash
# Check Remote VA services
kubectl get pods -n boulder -l app=remote-va

# Restart validation services
kubectl rollout restart deployment/boulder-va -n boulder
kubectl rollout restart deployment/remote-va1 -n boulder
kubectl rollout restart deployment/remote-va2 -n boulder
```

## Log Analysis

### Centralized Log Collection

```bash
# Get logs from all Boulder services
for service in wfe2 ra sa ca va publisher nonce-service; do
  echo "=== $service ===" >> boulder-logs.txt
  kubectl logs deployment/boulder-$service -n boulder >> boulder-logs.txt 2>&1
  echo "" >> boulder-logs.txt
done

# Get infrastructure logs
kubectl logs statefulset/mariadb -n boulder >> infrastructure-logs.txt 2>&1
kubectl logs deployment/proxysql -n boulder >> infrastructure-logs.txt 2>&1
kubectl logs statefulset/redis-0 -n boulder >> infrastructure-logs.txt 2>&1
```

### Log Analysis Patterns

```bash
# Search for errors
grep -i "error\|fatal\|panic" boulder-logs.txt

# Search for specific issues
grep -i "connection refused\|timeout\|authentication failed" boulder-logs.txt

# Search for certificate issues
grep -i "certificate\|tls\|ssl" boulder-logs.txt

# Search for database issues
grep -i "database\|sql\|connection" boulder-logs.txt
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

### Database Recovery

```bash
# Backup current database (if accessible)
kubectl exec -n boulder statefulset/mariadb -- \
  mysqldump -u root -p --all-databases > boulder-backup.sql

# Reset database (WARNING: destroys data)
kubectl delete statefulset mariadb -n boulder
kubectl delete pvc mariadb-data -n boulder
kubectl apply -f k8s/deployments/infrastructure/mariadb.yaml

# Wait for database to be ready
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
  statefulset/mariadb -n boulder --timeout=300s
```

### Complete Environment Reset

```bash
# Full environment cleanup and redeploy
kubectl delete namespace boulder
kubectl apply -f k8s/namespaces/boulder-namespace.yaml
./k8s/scripts/deploy.sh
```

## Performance Issues

### High Latency Troubleshooting

```bash
# Check response times
time curl -s http://localhost:4001/directory

# Monitor service latency
kubectl exec -n boulder deployment/boulder-wfe2 -- \
  curl -w "@/dev/stdin" -s http://localhost:8013/debug/vars <<< \
  "     time_namelookup:  %{time_namelookup}\n      time_connect:  %{time_connect}\n   time_appconnect:  %{time_appconnect}\n  time_pretransfer:  %{time_pretransfer}\n     time_redirect:  %{time_redirect}\n  time_starttransfer: %{time_starttransfer}\n                     ----------\n          time_total:  %{time_total}\n"

# Check database performance
kubectl exec -n boulder statefulset/mariadb -- \
  mysql -u root -p -e "SHOW PROCESSLIST;"
```

### Resource Optimization

```bash
# Optimize database connections
kubectl patch configmap boulder-sa-config -n boulder --type merge -p \
  '{"data":{"maxOpenConns":"100","maxIdleConns":"50","connMaxLifetime":"5m"}}'

# Scale high-traffic services
kubectl scale deployment boulder-wfe2 --replicas=3 -n boulder
kubectl scale deployment boulder-ra --replicas=3 -n boulder

# Enable horizontal pod autoscaling
kubectl autoscale deployment boulder-wfe2 --cpu-percent=70 --min=2 --max=10 -n boulder
```

---

This troubleshooting guide covers the most common issues encountered with Boulder Kubernetes deployment. For additional help, check the service logs and refer to the [Testing section](../README.md#testing) in the main README for validation procedures.