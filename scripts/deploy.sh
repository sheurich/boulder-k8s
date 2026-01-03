#!/usr/bin/env bash
# Deploy Boulder to Kubernetes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

OVERLAY="${1:-dev}"
NAMESPACE="${NAMESPACE:-boulder}"

log_info "Deploying Boulder with $OVERLAY overlay"

# Validate overlay exists
if [ ! -d "$ROOT_DIR/k8s/overlays/$OVERLAY" ]; then
    log_error "Overlay $OVERLAY not found"
    exit 1
fi

# Create namespace if it doesn't exist
run_silent "Namespace $NAMESPACE" sh -c "kubectl create namespace '$NAMESPACE' --dry-run=client -o yaml | kubectl apply -f -"

# Build required images (skip if SKIP_IMAGE_BUILD is set, e.g., in CI with pre-built images)
if [ "${SKIP_IMAGE_BUILD:-}" = "true" ]; then
    log_info "Skipping image build (SKIP_IMAGE_BUILD=true)"
    run_silent "Images loaded into kind" "$SCRIPT_DIR/build-images.sh" --load-only
else
    log_info "Building images..."
    run_silent "Images built and loaded" "$SCRIPT_DIR/build-images.sh"
fi

# Deploy infrastructure dependencies
log_info "Deploying infrastructure..."

# Deploy cert-manager CA infrastructure first (needed for Redis TLS)
run_silent "Internal CA applied" kubectl apply -f "$ROOT_DIR/k8s/overlays/$OVERLAY/cert-manager/internal-ca.yaml"

# Wait for internal CA to be ready
run_silent "Internal CA ready" kubectl wait --for=condition=ready certificate/boulder-internal-ca \
    -n "$NAMESPACE" --timeout=120s

# Deploy Redis TLS certificate
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: redis-tls
  namespace: $NAMESPACE
spec:
  secretName: redis-tls
  duration: 8760h
  renewBefore: 720h
  commonName: redis-master
  privateKey:
    algorithm: ECDSA
    size: 256
  dnsNames:
    - redis-master
    - redis-master.$NAMESPACE.svc.cluster.local
  issuerRef:
    name: boulder-internal-ca
    kind: Issuer
    group: cert-manager.io
EOF
log_ok "Redis TLS certificate created"

# Wait for Redis TLS certificate to be ready
run_silent "Redis TLS certificate ready" kubectl wait --for=condition=ready certificate/redis-tls \
    -n "$NAMESPACE" --timeout=120s

# Create MySQL TLS certificate (needed by MySQL before it starts)
run_silent "MySQL TLS certificate created" kubectl apply -f "$ROOT_DIR/k8s/components/db-proxysql/mysql-certificate.yaml"

# Create ProxySQL TLS certificate (needed by ProxySQL before it starts)
run_silent "ProxySQL TLS certificate created" kubectl apply -f "$ROOT_DIR/k8s/components/db-proxysql/proxysql-certificate.yaml"

# Wait for database TLS certificates to be ready
run_silent "MySQL TLS ready" kubectl wait --for=condition=ready certificate/mysql-tls \
    -n "$NAMESPACE" --timeout=120s
run_silent "ProxySQL TLS ready" kubectl wait --for=condition=ready certificate/proxysql-tls \
    -n "$NAMESPACE" --timeout=120s

# Deploy Redis
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
run_silent "Helm repo updated" helm repo update
run_silent "Redis installed" helm upgrade --install redis bitnami/redis \
    --namespace "$NAMESPACE" \
    --values "$ROOT_DIR/helm/redis/values-$OVERLAY.yaml" \
    --wait \
    --timeout 5m

# Cleanup immutable jobs before applying
run_silent "Old jobs cleaned up" kubectl delete job boulder-pki-ceremony boulder-db-migrate -n "$NAMESPACE" --ignore-not-found=true --wait=true

# Deploy Boulder services (includes PKI ceremony job)
log_info "Deploying Boulder services..."
run_silent "Boulder manifests applied" sh -c "kubectl kustomize '$ROOT_DIR/k8s/overlays/$OVERLAY' | kubectl apply -f -"

# Wait for PKI ceremony to complete (dev/dev-vitess only)
if [[ "$OVERLAY" == dev* ]]; then
    run_silent "PKI ceremony complete" kubectl wait --for=condition=complete job/boulder-pki-ceremony \
        -n "$NAMESPACE" --timeout=300s

    if kubectl get job -n "$NAMESPACE" boulder-db-migrate >/dev/null 2>&1; then
        log_info "Running DB migrations..."
        if ! kubectl wait --for=condition=complete job/boulder-db-migrate \
            -n "$NAMESPACE" --timeout=600s >/dev/null 2>&1; then
            log_fail "DB migration failed"
            kubectl logs job/boulder-db-migrate -n "$NAMESPACE" --all-containers 2>&1 || true
            exit 1
        fi
        log_ok "DB migrations complete"
    fi

    log_info "Restarting Boulder deployments..."
    mapfile -t boulder_deploys < <(
        kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/part-of=boulder -o name \
            | grep -v '/vitess$'
    )
    for deploy in "${boulder_deploys[@]}"; do
        kubectl rollout restart -n "$NAMESPACE" "$deploy" >/dev/null
    done
    kubectl rollout restart -n "$NAMESPACE" deployment/challtestsrv >/dev/null

    log_info "Waiting for core deployments..."
    core_deploys=(
        boulder-ca
        boulder-ra
        boulder-va
        boulder-rva1
        boulder-rva2
        boulder-rva3
        boulder-sa
        boulder-wfe2
        challtestsrv
    )
    for deploy in "${core_deploys[@]}"; do
        if kubectl get deployment -n "$NAMESPACE" "$deploy" >/dev/null 2>&1; then
            run_silent "$deploy ready" kubectl rollout status -n "$NAMESPACE" "deployment/$deploy" --timeout=120s
        fi
    done
fi

log_info "Deployment complete (namespace: $NAMESPACE, overlay: $OVERLAY)"
