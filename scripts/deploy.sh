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

# Deploy infrastructure dependencies
echo "==> Deploying infrastructure..."

# Deploy SoftHSM proxy (dev/staging only)
if [ "$OVERLAY" = "dev" ] || [ "$OVERLAY" = "staging" ]; then
    echo "  Installing SoftHSM proxy..."
    helm upgrade --install softhsm-proxy "$ROOT_DIR/helm/softhsm-proxy" \
        --namespace "$NAMESPACE" \
        --wait
fi

# Deploy Vitess
echo "  Installing Vitess..."
# Note: In real deployment, use official Vitess operator or helm chart
# For MVP, we'll use a simplified deployment
helm repo add vitess https://vitess.io/helm-charts 2>/dev/null || true
helm repo update
helm upgrade --install vitess vitess/vitess \
    --namespace "$NAMESPACE" \
    --values "$ROOT_DIR/helm/vitess/values-$OVERLAY.yaml" \
    --wait \
    --timeout 10m || echo "  ⚠ Vitess deployment skipped (chart may not be available)"

# Deploy Redis
echo "  Installing Redis..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update
helm upgrade --install redis bitnami/redis \
    --namespace "$NAMESPACE" \
    --values "$ROOT_DIR/helm/redis/values-$OVERLAY.yaml" \
    --wait \
    --timeout 5m

# Run PKI ceremony (dev only)
if [ "$OVERLAY" = "dev" ]; then
    echo "==> Running PKI ceremony..."
    kubectl apply -n "$NAMESPACE" -f "$ROOT_DIR/k8s/overlays/$OVERLAY/ceremony/"
    kubectl wait --for=condition=complete job/boulder-pki-ceremony \
        -n "$NAMESPACE" --timeout=300s || true
fi

# Deploy Boulder services
echo "==> Deploying Boulder services..."
kubectl apply -k "$ROOT_DIR/k8s/overlays/$OVERLAY"

echo "==> Deployment complete"
echo "  Namespace: $NAMESPACE"
echo "  Overlay: $OVERLAY"
