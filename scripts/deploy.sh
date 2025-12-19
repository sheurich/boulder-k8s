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

# Build required images
echo "==> Building required images..."
"$SCRIPT_DIR/build-images.sh"

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

# Deploy Boulder services (includes PKI ceremony job)
echo "==> Deploying Boulder services..."
kubectl apply -k "$ROOT_DIR/k8s/overlays/$OVERLAY"

# Wait for PKI ceremony to complete (dev/dev-vitess only)
if [[ "$OVERLAY" == dev* ]]; then
    echo "==> Waiting for PKI ceremony..."
    kubectl wait --for=condition=complete job/boulder-pki-ceremony \
        -n "$NAMESPACE" --timeout=300s
fi

echo "==> Deployment complete"
echo "  Namespace: $NAMESPACE"
echo "  Overlay: $OVERLAY"
