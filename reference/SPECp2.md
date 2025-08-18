# Phase 2 Spec: Multi-Environment & CI-Compatible Deployment

> **Navigation:** See [`README.md`](../README.md) for project overview | [`SPECp1.md`](SPECp1.md) for Phase 1 foundation | **Note:** Phase 2 extends Phase 1, not replaces it

## Objective

Extend the Kubernetes-based Boulder integration environment to support deployment in:

- Local development (kind)
- CI/CD environments (GitHub Actions, etc.)
- Production-like environments (e.g., GKE)

This phase builds upon the foundational work completed in Phase 1, enhancing it with production-ready features, multi-environment support, and enterprise-grade security through Hardware Security Module (HSM) integration.

## Architecture Overview

Phase 2 transforms the basic Phase 1 deployment into a production-ready, multi-environment system:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Phase 2 Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Development │  │   Staging   │  │      Production         │  │
│  │    (kind)   │  │   (k8s)     │  │       (GKE/EKS)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│         │                │                        │            │
│         └────────────────┼────────────────────────┘            │
│                          │                                     │
│  ┌─────────────────────────────────────────────────────────────┤
│  │              Shared Components                              │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐│
│  │  │ Kustomize   │  │  CI/CD       │  │   Monitoring &      ││
│  │  │ Overlays    │  │  Pipeline    │  │   Observability     ││
│  │  └─────────────┘  └──────────────┘  └─────────────────────┘│
│  └─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┤
│  │                 Security Layer                              │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐│
│  │  │  Network    │  │     HSM      │  │   Secret Rotation   ││
│  │  │  Policies   │  │ Integration  │  │   & Management      ││
│  │  └─────────────┘  └──────────────┘  └─────────────────────┘│
│  └─────────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────────┘
```

## HSM Integration Architecture

### Overview

Phase 2 replaces the development-focused SoftHSM2 file-based approach from Phase 1 with a production-ready network HSM architecture using `vegardit/softhsm2-pkcs11-proxy`.

### Architecture Components

```yaml
# HSM Network Architecture
apiVersion: v1
kind: ConfigMap
metadata:
  name: hsm-architecture-config
data:
  architecture.yaml: |
    network_hsm:
      # HSM Proxy Service (replaces Phase 1 file-based HSM)
      proxy_service:
        image: vegardit/softhsm2-pkcs11-proxy:latest
        replicas: 2  # HA configuration
        ports:
          - name: pkcs11-proxy
            port: 5657
            protocol: TCP
        
      # TLS-PSK Authentication
      authentication:
        method: TLS-PSK
        psk_secret: hsm-psk-credentials
        mutual_tls: true
        
      # Load Balancer for HA
      load_balancer:
        type: internal
        algorithm: round_robin
        health_check:
          path: /health
          interval: 30s
```

### HSM Service Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hsm-proxy
  namespace: boulder-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hsm-proxy
  template:
    metadata:
      labels:
        app: hsm-proxy
    spec:
      containers:
        - name: hsm-proxy
          image: vegardit/softhsm2-pkcs11-proxy:latest
          ports:
            - containerPort: 5657
              name: pkcs11-proxy
          env:
            - name: PKCS11_PROXY_TLS_PSK_FILE
              value: /etc/hsm-secrets/psk.key
            - name: PKCS11_PROXY_SOCKET
              value: "0.0.0.0:5657"
          volumeMounts:
            - name: hsm-secrets
              mountPath: /etc/hsm-secrets
              readOnly: true
            - name: hsm-tokens
              mountPath: /var/lib/softhsm/tokens
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "200m"
          livenessProbe:
            tcpSocket:
              port: 5657
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            tcpSocket:
              port: 5657
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: hsm-secrets
          secret:
            secretName: hsm-psk-credentials
        - name: hsm-tokens
          persistentVolumeClaim:
            claimName: hsm-storage
```

### Boulder CA HSM Configuration

Boulder CA services are configured to use the network HSM via `libpkcs11-proxy.so`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-ca-hsm-config
data:
  ca-config.yaml: |
    ca:
      # Network HSM Configuration
      pkcs11:
        module: "/usr/lib/x86_64-linux-gnu/libpkcs11-proxy.so"
        psk_secret_file: "/etc/hsm-credentials/psk.key"
        slot: 0
        pin_file: "/etc/hsm-credentials/pin.txt"
        servers:
          - hsm-proxy-1.boulder-system.svc.cluster.local:5657
          - hsm-proxy-2.boulder-system.svc.cluster.local:5657
        connection_pool:
          max_connections: 10
          connection_timeout: 30s
          retry_attempts: 3
      
      # Key Management
      key_management:
        root_ca_key:
          label: "boulder-root-ca"
          key_type: "RSA"
          key_size: 4096
        intermediate_ca_key:
          label: "boulder-intermediate-ca"
          key_type: "RSA" 
          key_size: 2048
        
      # Rotation Policy
      key_rotation:
        intermediate_ca:
          rotation_interval: "90d"
          overlap_period: "7d"
        ocsp_signing:
          rotation_interval: "30d"
          overlap_period: "1d"
```

### HSM High Availability

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hsm-proxy-lb
  namespace: boulder-system
spec:
  selector:
    app: hsm-proxy
  ports:
    - port: 5657
      targetPort: 5657
      name: pkcs11-proxy
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 86400 # 24 hours
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: hsm-proxy-pdb
  namespace: boulder-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: hsm-proxy
```

## Environment-Specific Overlays

### Directory Structure

```
overlays/
├── base/                    # Base Kustomization
│   ├── kustomization.yaml
│   └── resources/
├── development/             # Development overlay (kind)
│   ├── kustomization.yaml
│   ├── patches/
│   │   ├── resource-limits.yaml
│   │   ├── replicas.yaml
│   │   └── storage.yaml
│   └── secrets/
│       └── dev-secrets.yaml
├── staging/                 # Staging overlay
│   ├── kustomization.yaml
│   ├── patches/
│   │   ├── resource-limits.yaml
│   │   ├── replicas.yaml
│   │   ├── networking.yaml
│   │   └── monitoring.yaml
│   └── secrets/
│       └── staging-secrets.yaml
└── production/              # Production overlay
    ├── kustomization.yaml
    ├── patches/
    │   ├── resource-limits.yaml
    │   ├── replicas.yaml
    │   ├── networking.yaml
    │   ├── security-policies.yaml
    │   └── monitoring.yaml
    └── secrets/
        └── production-secrets.yaml
```

### Base Kustomization

```yaml
# overlays/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: boulder-base

resources:
  - ../../manifests/namespace.yaml
  - ../../manifests/configmaps.yaml
  - ../../manifests/secrets.yaml
  - ../../manifests/services.yaml
  - ../../manifests/deployments.yaml
  - ../../manifests/storage.yaml

commonLabels:
  app.kubernetes.io/name: boulder
  app.kubernetes.io/version: "v1.0.0"

configMapGenerator:
  - name: boulder-config
    files:
      - config/boulder.yaml
      - config/database.yaml
      - config/redis.yaml
```

### Development Overlay

```yaml
# overlays/development/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: boulder-development

resources:
  - ../base

namePrefix: dev-

commonLabels:
  environment: development

images:
  - name: boulder
    newTag: latest

patches:
  - path: patches/resource-limits.yaml
    target:
      kind: Deployment
  - path: patches/replicas.yaml
    target:
      kind: Deployment
  - path: patches/storage.yaml
    target:
      kind: PersistentVolumeClaim

configMapGenerator:
  - name: environment-config
    literals:
      - ENVIRONMENT=development
      - LOG_LEVEL=debug
      - ENABLE_PROFILING=true
      - HSM_MODE=softhsm2
```

### Development Resource Limits

```yaml
# overlays/development/patches/resource-limits.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: boulder-ca-1
spec:
  template:
    spec:
      containers:
        - name: boulder-ca
          resources:
            requests:
              memory: "128Mi"
              cpu: "50m"
            limits:
              memory: "256Mi"
              cpu: "100m"
```

### Staging Overlay

```yaml
# overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: boulder-staging

resources:
  - ../base

namePrefix: staging-

commonLabels:
  environment: staging

images:
  - name: boulder
    newTag: staging-latest

patches:
  - path: patches/resource-limits.yaml
  - path: patches/replicas.yaml
  - path: patches/networking.yaml
  - path: patches/monitoring.yaml

configMapGenerator:
  - name: environment-config
    literals:
      - ENVIRONMENT=staging
      - LOG_LEVEL=info
      - ENABLE_PROFILING=false
      - HSM_MODE=network
      - METRICS_ENABLED=true
```

### Production Overlay

```yaml
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: boulder-production

resources:
  - ../base

namePrefix: prod-

commonLabels:
  environment: production

images:
  - name: boulder
    newTag: v1.2.3 # Specific version tags for production

patches:
  - path: patches/resource-limits.yaml
  - path: patches/replicas.yaml
  - path: patches/networking.yaml
  - path: patches/security-policies.yaml
  - path: patches/monitoring.yaml

configMapGenerator:
  - name: environment-config
    literals:
      - ENVIRONMENT=production
      - LOG_LEVEL=warn
      - ENABLE_PROFILING=false
      - HSM_MODE=network
      - METRICS_ENABLED=true
      - AUDIT_LOGGING=true

secretGenerator:
  - name: production-secrets
    files:
      - secrets/database-credentials.env
      - secrets/hsm-credentials.env
      - secrets/tls-certificates.env
```

### Production Resource Configuration

```yaml
# overlays/production/patches/resource-limits.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: boulder-ca-1
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: boulder-ca
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: boulder-ra-1
spec:
  replicas: 5
  template:
    spec:
      containers:
        - name: boulder-ra
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "1Gi"
              cpu: "500m"
```

## CI/CD Workflow Implementation

### GitOps Architecture

```yaml
# .github/workflows/cicd.yaml
name: Boulder K8s CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/boulder

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Kind
        uses: helm/kind-action@v1.8.0
        with:
          cluster_name: boulder-test

      - name: Build Boulder Image
        run: |
          docker build -t $REGISTRY/$IMAGE_NAME:$GITHUB_SHA .
          kind load docker-image $REGISTRY/$IMAGE_NAME:$GITHUB_SHA --name boulder-test

      - name: Deploy to Kind
        run: |
          cd overlays/development
          kustomize edit set image boulder=$REGISTRY/$IMAGE_NAME:$GITHUB_SHA
          kustomize build . | kubectl apply -f -

      - name: Wait for Deployment
        run: |
          kubectl wait --for=condition=available --timeout=300s deployment/dev-boulder-ca-1
          kubectl wait --for=condition=available --timeout=300s deployment/dev-boulder-ra-1

      - name: Run Integration Tests
        run: |
          kubectl create job --from=cronjob/boulder-integration-tests integration-test-$GITHUB_RUN_ID
          kubectl wait --for=condition=complete --timeout=1800s job/integration-test-$GITHUB_RUN_ID
          kubectl logs job/integration-test-$GITHUB_RUN_ID

      - name: Collect Logs on Failure
        if: failure()
        run: |
          kubectl get pods
          kubectl describe pods
          kubectl logs -l app=boulder --tail=1000

  build-and-push:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: Login to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and Push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            $REGISTRY/$IMAGE_NAME:latest
            $REGISTRY/$IMAGE_NAME:${{ github.sha }}

  deploy-staging:
    needs: build-and-push
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment:
      name: staging
      url: https://staging-boulder.example.com
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to Staging
        run: |
          cd overlays/staging
          kustomize edit set image boulder=$REGISTRY/$IMAGE_NAME:${{ github.sha }}
          kustomize build . | kubectl apply -f -

      - name: Verify Staging Deployment
        run: |
          kubectl rollout status deployment/staging-boulder-ca-1 --timeout=300s
          kubectl rollout status deployment/staging-boulder-ra-1 --timeout=300s

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment:
      name: production
      url: https://boulder.example.com
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to Production
        run: |
          cd overlays/production
          kustomize edit set image boulder=$REGISTRY/$IMAGE_NAME:${{ github.sha }}
          kustomize build . | kubectl apply -f -

      - name: Verify Production Deployment
        run: |
          kubectl rollout status deployment/prod-boulder-ca-1 --timeout=600s
          kubectl rollout status deployment/prod-boulder-ra-1 --timeout=600s
```

### ArgoCD GitOps Configuration

```yaml
# argocd/applications/boulder-staging.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: boulder-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/example/boulder-k8s
    targetRevision: main
    path: overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: boulder-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  revisionHistoryLimit: 10
```

### Rollback Procedures

```bash
#!/bin/bash
# scripts/rollback.sh

set -euo pipefail

ENVIRONMENT=${1:-staging}
PREVIOUS_VERSION=${2:-$(kubectl get deployment -n boulder-${ENVIRONMENT} -o jsonpath='{.items[0].metadata.annotations.deployment\.kubernetes\.io/revision}' | xargs -I {} expr {} - 1)}

echo "Rolling back Boulder ${ENVIRONMENT} to revision ${PREVIOUS_VERSION}"

# Rollback all deployments
for deployment in $(kubectl get deployments -n boulder-${ENVIRONMENT} -l app=boulder -o name); do
    echo "Rolling back ${deployment}"
    kubectl rollout undo ${deployment} -n boulder-${ENVIRONMENT} --to-revision=${PREVIOUS_VERSION}
done

# Wait for rollback to complete
for deployment in $(kubectl get deployments -n boulder-${ENVIRONMENT} -l app=boulder -o name); do
    echo "Waiting for ${deployment} rollback to complete"
    kubectl rollout status ${deployment} -n boulder-${ENVIRONMENT} --timeout=300s
done

echo "Rollback completed successfully"
```

## Service Configuration Examples

### Boulder CA Service Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-ca-config
data:
  config.yaml: |
    # Development Configuration
    ca:
      # Database Configuration
      database:
        host: postgresql.boulder-system.svc.cluster.local
        port: 5432
        name: boulder_sa
        pool_size: 5
        max_idle_conns: 2
        max_open_conns: 10
        conn_max_lifetime: 3600s
        
      # Redis Configuration  
      redis:
        host: redis.boulder-system.svc.cluster.local
        port: 6379
        pool_size: 10
        
      # Rate Limiting
      rate_limits:
        certificates_per_name:
          window: 168h  # 7 days
          threshold: 50
        certificates_per_fqdn_set:
          window: 168h
          threshold: 5
          
      # Certificate Profiles
      certificate_profiles:
        end_entity:
          max_validity: 7776000s  # 90 days
          ocsp_url: "http://ocsp.boulder.service.consul/ocsp"
          crl_url: "http://crl.boulder.service.consul/crl"
        
      # OCSP Configuration
      ocsp:
        signing_cert_validity: 2592000s  # 30 days
        response_validity: 604800s       # 7 days
---
# Staging Configuration Override
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-ca-config-staging
data:
  config.yaml: |
    ca:
      database:
        pool_size: 20
        max_idle_conns: 5
        max_open_conns: 40
      redis:
        pool_size: 25
      rate_limits:
        certificates_per_name:
          threshold: 100
        certificates_per_fqdn_set:
          threshold: 10
---
# Production Configuration Override
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-ca-config-production
data:
  config.yaml: |
    ca:
      database:
        pool_size: 50
        max_idle_conns: 10
        max_open_conns: 100
        conn_max_lifetime: 7200s
      redis:
        pool_size: 50
      rate_limits:
        certificates_per_name:
          threshold: 300
        certificates_per_fqdn_set:
          threshold: 50
      certificate_profiles:
        end_entity:
          max_validity: 7776000s  # 90 days production
```

### Boulder RA Service Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-ra-config
data:
  config.yaml: |
    ra:
      # Database Configuration
      database:
        host: postgresql.boulder-system.svc.cluster.local
        port: 5432
        name: boulder_sa
        pool_size: 10
        max_idle_conns: 3
        max_open_conns: 20
        
      # Rate Limiting Configuration
      rate_limits:
        registrations_per_ip:
          window: 3600s     # 1 hour
          threshold: 10     # Dev: relaxed limits
        certificates_per_registration:
          window: 3600s
          threshold: 5
        failed_authorizations_per_hostname:
          window: 3600s
          threshold: 5
          
      # Challenge Configuration
      challenges:
        http_01:
          enabled: true
          timeout: 30s
          max_redirects: 10
        dns_01:
          enabled: true
          timeout: 120s
        tls_alpn_01:
          enabled: true
          timeout: 30s
          
      # VA Configuration
      va_service:
        timeout: 30s
        max_retries: 3
        service_url: "boulder-va.boulder-system.svc.cluster.local:9092"
        
      # CA Configuration  
      ca_service:
        timeout: 30s
        service_url: "boulder-ca-1.boulder-system.svc.cluster.local:9093"
        backup_service_url: "boulder-ca-2.boulder-system.svc.cluster.local:9093"
```

### Environment-Specific RA Overrides

```yaml
# Staging RA Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-ra-config-staging
data:
  config.yaml: |
    ra:
      database:
        pool_size: 25
        max_open_conns: 50
      rate_limits:
        registrations_per_ip:
          threshold: 20
        certificates_per_registration:
          threshold: 10
        failed_authorizations_per_hostname:
          threshold: 10
---
# Production RA Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-ra-config-production
data:
  config.yaml: |
    ra:
      database:
        pool_size: 50
        max_open_conns: 100
      rate_limits:
        registrations_per_ip:
          threshold: 50        # Production: higher limits
        certificates_per_registration:
          threshold: 20
        failed_authorizations_per_hostname:
          threshold: 20
      challenges:
        http_01:
          timeout: 60s         # Production: longer timeouts
        dns_01:
          timeout: 300s
        tls_alpn_01:
          timeout: 60s
```

## Monitoring and Observability

### Prometheus Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      
    rule_files:
      - "/etc/prometheus/rules/*.yml"
      
    scrape_configs:
      # Boulder Services
      - job_name: 'boulder-ca'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          action: keep
          regex: boulder-ca
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          target_label: __address__
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          
      - job_name: 'boulder-ra'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          action: keep
          regex: boulder-ra
          
      - job_name: 'boulder-va'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          action: keep
          regex: boulder-va
          
      # Infrastructure
      - job_name: 'postgresql'
        static_configs:
        - targets: ['postgresql-exporter.boulder-system.svc.cluster.local:9187']
        
      - job_name: 'redis'
        static_configs:
        - targets: ['redis-exporter.boulder-system.svc.cluster.local:9121']
        
      # HSM Monitoring
      - job_name: 'hsm-proxy'
        static_configs:
        - targets: ['hsm-proxy.boulder-system.svc.cluster.local:8080']
        
    alerting:
      alertmanagers:
      - static_configs:
        - targets:
          - alertmanager.monitoring.svc.cluster.local:9093
```

### Boulder Metrics Annotations

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: boulder-ca-1
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
        - name: boulder-ca
          ports:
            - containerPort: 8080
              name: metrics
          env:
            - name: BOULDER_METRICS_ENABLED
              value: "true"
            - name: BOULDER_METRICS_PORT
              value: "8080"
```

### Alerting Rules

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-alerting-rules
data:
  boulder.yml: |
    groups:
    - name: boulder.rules
      rules:
      
      # Certificate Issuance Alerts
      - alert: BoulderHighCertificateIssuanceRate
        expr: rate(boulder_ca_certificates_issued_total[5m]) > 100
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High certificate issuance rate detected"
          description: "Boulder CA is issuing certificates at {{ $value }} certs/second"
          
      - alert: BoulderCertificateIssuanceFailure
        expr: rate(boulder_ca_certificate_issuance_failures_total[5m]) > 10
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Certificate issuance failures detected"
          
      # Database Alerts
      - alert: BoulderDatabaseConnectionFailure
        expr: boulder_database_connections_failed_total > 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "Database connection failures"
          
      - alert: BoulderDatabaseHighLatency
        expr: histogram_quantile(0.95, boulder_database_query_duration_seconds_bucket) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High database query latency"
          
      # HSM Alerts
      - alert: BoulderHSMConnectionFailure
        expr: boulder_hsm_operations_failed_total > 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "HSM connection or operation failures"
          
      - alert: BoulderHSMHighLatency  
        expr: histogram_quantile(0.95, boulder_hsm_operation_duration_seconds_bucket) > 5
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High HSM operation latency"
          
      # Service Health Alerts
      - alert: BoulderServiceDown
        expr: up{job=~"boulder-.*"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Boulder service is down"
          description: "{{ $labels.job }} has been down for more than 1 minute"
```

### Grafana Dashboard Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: boulder-dashboard
data:
  boulder-overview.json: |
    {
      "dashboard": {
        "id": null,
        "title": "Boulder ACME CA Overview",
        "tags": ["boulder", "acme", "ca"],
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "Certificate Issuance Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(boulder_ca_certificates_issued_total[5m])",
                "legendFormat": "Certificates/sec"
              }
            ],
            "yAxes": [
              {
                "label": "Certificates per second",
                "min": 0
              }
            ]
          },
          {
            "id": 2,
            "title": "Active Authorizations",
            "type": "stat",
            "targets": [
              {
                "expr": "boulder_ra_authorizations_active",
                "legendFormat": "Active Authorizations"
              }
            ]
          },
          {
            "id": 3,
            "title": "Database Connection Pool",
            "type": "graph",
            "targets": [
              {
                "expr": "boulder_database_connections_active",
                "legendFormat": "Active Connections"
              },
              {
                "expr": "boulder_database_connections_idle",
                "legendFormat": "Idle Connections"
              }
            ]
          },
          {
            "id": 4,
            "title": "HSM Operations",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(boulder_hsm_operations_total[5m])",
                "legendFormat": "HSM Ops/sec"
              },
              {
                "expr": "rate(boulder_hsm_operations_failed_total[5m])",
                "legendFormat": "HSM Failures/sec"  
              }
            ]
          }
        ]
      }
    }
```

### Log Aggregation

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
data:
  fluent.conf: |
    <source>
      @type kubernetes_metadata
      @label @mainstream
      kubernetes_url https://kubernetes.default.svc.cluster.local:443
      verify_ssl true
      ca_file /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file /var/run/secrets/kubernetes.io/serviceaccount/token
    </source>

    <label @mainstream>
      <match kubernetes.var.log.containers.boulder-**>
        @type elasticsearch
        host elasticsearch.logging.svc.cluster.local
        port 9200
        index_name boulder-logs
        type_name boulder
        logstash_format true
        logstash_prefix boulder
        
        <buffer>
          @type file
          path /var/log/fluentd-buffers/boulder.buffer
          flush_mode interval
          retry_type exponential_backoff
          flush_thread_count 2
          flush_interval 5s
          retry_forever
          retry_max_interval 30
          chunk_limit_size 2M
          queue_limit_length 8
          overflow_action block
        </buffer>
      </match>
    </label>
```

## Security Hardening

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: boulder-ca-network-policy
  namespace: boulder-system
spec:
  podSelector:
    matchLabels:
      app: boulder-ca
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow RA to communicate with CA
    - from:
        - podSelector:
            matchLabels:
              app: boulder-ra
      ports:
        - protocol: TCP
          port: 9093
    # Allow monitoring
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow CA to communicate with database
    - to:
        - podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
    # Allow CA to communicate with HSM
    - to:
        - podSelector:
            matchLabels:
              app: hsm-proxy
      ports:
        - protocol: TCP
          port: 5657
    # Allow DNS resolution
    - to: []
      ports:
        - protocol: UDP
          port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: boulder-ra-network-policy
  namespace: boulder-system
spec:
  podSelector:
    matchLabels:
      app: boulder-ra
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow WFE to communicate with RA
    - from:
        - podSelector:
            matchLabels:
              app: boulder-wfe
      ports:
        - protocol: TCP
          port: 9094
  egress:
    # Allow RA to communicate with CA
    - to:
        - podSelector:
            matchLabels:
              app: boulder-ca
      ports:
        - protocol: TCP
          port: 9093
    # Allow RA to communicate with VA
    - to:
        - podSelector:
            matchLabels:
              app: boulder-va
      ports:
        - protocol: TCP
          port: 9092
```

### Pod Security Standards

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: boulder-ca-1
  annotations:
    seccomp.security.alpha.kubernetes.io/pod: runtime/default
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: boulder-ca
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        runAsUser: 1000
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/cache
  volumes:
    - name: tmp
      emptyDir: {}
    - name: cache
      emptyDir: {}
```

### Secret Rotation Automation

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: secret-rotation
  namespace: boulder-system
spec:
  schedule: "0 2 * * 0" # Weekly on Sunday 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: secret-rotator
              image: secret-rotator:latest
              env:
                - name: ROTATION_POLICY
                  value: "weekly"
                - name: SECRET_BACKEND
                  value: "kubernetes"
              command:
                - /bin/sh
                - -c
                - |
                  # Rotate database passwords
                  kubectl create secret generic postgresql-credentials-new \
                    --from-literal=username=boulder \
                    --from-literal=password=$(openssl rand -base64 32)

                  # Update deployments to use new secret
                  kubectl patch deployment boulder-ca-1 -p \
                    '{"spec":{"template":{"spec":{"containers":[{"name":"boulder-ca","env":[{"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"name":"postgresql-credentials-new","key":"password"}}}]}]}}}}'

                  # Wait for rollout
                  kubectl rollout status deployment/boulder-ca-1

                  # Remove old secret
                  kubectl delete secret postgresql-credentials-old || true
                  kubectl label secret postgresql-credentials postgresql-credentials-old
                  kubectl label secret postgresql-credentials-new postgresql-credentials
          restartPolicy: OnFailure
```

### Audit Logging

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: audit-policy
data:
  audit-policy.yaml: |
    apiVersion: audit.k8s.io/v1
    kind: Policy
    rules:
    # Log certificate operations at RequestResponse level
    - level: RequestResponse
      namespaces: ["boulder-system"]
      verbs: ["create", "update", "patch", "delete"]
      resources:
      - group: ""
        resources: ["secrets", "configmaps"]
      - group: "apps"
        resources: ["deployments"]
        
    # Log HSM operations
    - level: RequestResponse
      namespaces: ["boulder-system"]
      verbs: ["create", "update", "delete"]
      resources:
      - group: ""
        resources: ["pods"]
      resourceNames: ["hsm-proxy-*"]
      
    # Metadata level for read operations
    - level: Metadata
      namespaces: ["boulder-system"]
      verbs: ["get", "list", "watch"]
```

## Performance Optimization

### Horizontal Pod Autoscaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: boulder-ra-hpa
  namespace: boulder-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: boulder-ra-1
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
    - type: Pods
      pods:
        metric:
          name: boulder_ra_pending_authorizations
        target:
          type: AverageValue
          averageValue: "50"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Percent
          value: 100
          periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 10
          periodSeconds: 60
```

### Database Connection Pooling

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgbouncer-config
data:
  pgbouncer.ini: |
    [databases]
    boulder_sa = host=postgresql.boulder-system.svc.cluster.local port=5432 dbname=boulder_sa

    [pgbouncer]
    listen_addr = 0.0.0.0
    listen_port = 6432
    auth_type = md5
    auth_file = /etc/pgbouncer/userlist.txt

    # Connection pool settings
    pool_mode = transaction
    server_reset_query = DISCARD ALL
    max_client_conn = 1000
    default_pool_size = 25
    reserve_pool_size = 5
    reserve_pool_timeout = 5

    # Performance tuning
    server_lifetime = 3600
    server_idle_timeout = 600
    server_connect_timeout = 15
    server_login_retry = 15
    client_login_timeout = 60

    # Logging
    log_connections = 1
    log_disconnections = 1
    log_stats = 1
    stats_period = 60

  userlist.txt: |
    "boulder" "md5secrethash"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
  namespace: boulder-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pgbouncer
  template:
    metadata:
      labels:
        app: pgbouncer
    spec:
      containers:
        - name: pgbouncer
          image: pgbouncer/pgbouncer:latest
          ports:
            - containerPort: 6432
          volumeMounts:
            - name: config
              mountPath: /etc/pgbouncer
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "100m"
      volumes:
        - name: config
          configMap:
            name: pgbouncer-config
```

### Redis Sharding Strategy

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-cluster-config
data:
  redis.conf: |
    # Redis Cluster Configuration
    port 6379
    cluster-enabled yes
    cluster-config-file nodes.conf
    cluster-node-timeout 5000
    appendonly yes

    # Memory optimization
    maxmemory 1gb
    maxmemory-policy allkeys-lru

    # Performance tuning
    tcp-keepalive 300
    timeout 0
    tcp-backlog 511

    # Persistence
    save 900 1
    save 300 10
    save 60 10000

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-cluster
  namespace: boulder-system
spec:
  serviceName: redis-cluster
  replicas: 6
  selector:
    matchLabels:
      app: redis-cluster
  template:
    metadata:
      labels:
        app: redis-cluster
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
              name: client
            - containerPort: 16379
              name: gossip
          command:
            - redis-server
            - /etc/redis/redis.conf
          volumeMounts:
            - name: config
              mountPath: /etc/redis
            - name: data
              mountPath: /data
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "1Gi"
              cpu: "500m"
      volumes:
        - name: config
          configMap:
            name: redis-cluster-config
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

### Load Balancer Tuning

```yaml
apiVersion: v1
kind: Service
metadata:
  name: boulder-wfe-lb
  namespace: boulder-system
  annotations:
    # GCP Load Balancer specific annotations
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"default": "boulder-wfe-backend-config"}'
    # Session affinity for ACME flows
    service.alpha.kubernetes.io/session-affinity: "ClientIP"
    service.alpha.kubernetes.io/session-affinity-timeout: "3600"
spec:
  type: LoadBalancer
  selector:
    app: boulder-wfe
  ports:
    - name: http
      port: 80
      targetPort: 4000
      protocol: TCP
    - name: https
      port: 443
      targetPort: 4001
      protocol: TCP
---
# Backend configuration for advanced load balancing
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: boulder-wfe-backend-config
  namespace: boulder-system
spec:
  timeoutSec: 30
  connectionDraining:
    drainingTimeoutSec: 60
  healthCheck:
    checkIntervalSec: 10
    timeoutSec: 5
    healthyThreshold: 1
    unhealthyThreshold: 3
    type: HTTP
    requestPath: /build
    port: 4000
  sessionAffinity:
    affinityType: "CLIENT_IP"
    affinityCookieTtlSec: 3600
```

## Implementation Timeline

### Phase 2.1: Foundation (Weeks 1-2)

- [ ] Implement HSM network architecture with `vegardit/softhsm2-pkcs11-proxy`
- [ ] Set up Kustomize overlay structure for dev/staging/production
- [ ] Create base CI/CD pipeline with GitHub Actions

### Phase 2.2: Multi-Environment Support (Weeks 3-4)

- [ ] Complete environment-specific configurations
- [ ] Implement secret rotation automation
- [ ] Set up monitoring and alerting infrastructure

### Phase 2.3: Security Hardening (Weeks 5-6)

- [ ] Implement network policies and pod security standards
- [ ] Set up audit logging and compliance monitoring
- [ ] Complete HSM integration testing

### Phase 2.4: Performance Optimization (Weeks 7-8)

- [ ] Implement autoscaling and performance tuning
- [ ] Set up advanced load balancing and connection pooling
- [ ] Complete end-to-end performance testing

### Phase 2.5: Production Readiness (Weeks 9-10)

- [ ] Complete GitOps implementation with ArgoCD
- [ ] Implement comprehensive monitoring and observability
- [ ] Complete production deployment and validation

## Success Criteria

Phase 2 implementation will be considered successful when:

1. **Multi-Environment Support**: All three environments (dev/staging/production) deploy successfully with appropriate configurations
2. **HSM Integration**: Network HSM replaces Phase 1 file-based approach with proper TLS-PSK authentication
3. **CI/CD Pipeline**: Automated testing and deployment pipeline functions correctly across all environments
4. **Monitoring**: Complete observability stack provides actionable insights into system health and performance
5. **Security**: All security hardening measures are implemented and validated
6. **Performance**: System meets performance requirements under production-level load
7. **Documentation**: All implementation details are documented for operational teams

## Deliverables

- `overlays/` directory with complete Kustomize environment configurations
- `.github/workflows/` directory with CI/CD pipeline definitions
- `monitoring/` directory with Prometheus/Grafana configurations
- `security/` directory with network policies and security configurations
- `scripts/` directory with operational automation scripts
- Updated `README.md` with Phase 2 deployment and operational procedures
- Complete HSM integration documentation and runbooks
