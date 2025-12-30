#!/usr/bin/env bash
# Deploy Boulder to Kubernetes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

OVERLAY="${1:-dev}"
NAMESPACE="${NAMESPACE:-boulder}"

echo "==> Deploying Boulder with $OVERLAY overlay"

# Validate overlay exists
if [ ! -d "$ROOT_DIR/k8s/overlays/$OVERLAY" ]; then
    echo "Error: Overlay $OVERLAY not found"
    exit 1
fi

# Create namespace if it doesn't exist
echo "==> Creating namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Build required images (skip if SKIP_IMAGE_BUILD is set, e.g., in CI with pre-built images)
if [ "${SKIP_IMAGE_BUILD:-}" = "true" ]; then
    echo "==> Skipping image build (SKIP_IMAGE_BUILD=true)"
    echo "==> Loading pre-built images into kind..."
    "$SCRIPT_DIR/build-images.sh" --load-only
else
    echo "==> Building required images..."
    "$SCRIPT_DIR/build-images.sh"
fi

# Deploy infrastructure dependencies
echo "==> Deploying infrastructure..."

# Deploy Redis
echo "  Installing Redis..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update
helm upgrade --install redis bitnami/redis \
    --namespace "$NAMESPACE" \
    --values "$ROOT_DIR/helm/redis/values-$OVERLAY.yaml" \
    --wait \
    --timeout 5m

# Cleanup immutable jobs before applying
echo "==> Cleaning up old jobs..."
kubectl delete job boulder-pki-ceremony boulder-db-migrate -n "$NAMESPACE" --ignore-not-found=true --wait=true

# Deploy Boulder services (includes PKI ceremony job)
echo "==> Deploying Boulder services..."
kubectl kustomize "$ROOT_DIR/k8s/overlays/$OVERLAY" --load-restrictor LoadRestrictionsNone | kubectl apply -f -

# Wait for PKI ceremony to complete (dev/dev-vitess only)
if [[ "$OVERLAY" == dev* ]]; then
    echo "==> Waiting for PKI ceremony..."
    kubectl wait --for=condition=complete job/boulder-pki-ceremony \
        -n "$NAMESPACE" --timeout=300s

    echo "==> Waiting for DB migrations..."
    if kubectl get job -n "$NAMESPACE" boulder-db-migrate >/dev/null 2>&1; then
        kubectl wait --for=condition=complete job/boulder-db-migrate \
            -n "$NAMESPACE" --timeout=600s
    fi

    echo "==> Restarting Boulder deployments to pick up new certs..."
    mapfile -t boulder_deploys < <(
        kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/part-of=boulder -o name \
            | grep -v '/vitess$'
    )
    for deploy in "${boulder_deploys[@]}"; do
        kubectl rollout restart -n "$NAMESPACE" "$deploy"
    done
    kubectl rollout restart -n "$NAMESPACE" deployment/challtestsrv

    echo "==> Waiting for core Boulder deployments..."
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
            kubectl rollout status -n "$NAMESPACE" "deployment/$deploy" --timeout=120s
        fi
    done
fi

echo "==> Deployment complete"
echo "  Namespace: $NAMESPACE"
echo "  Overlay: $OVERLAY"
