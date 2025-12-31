#!/usr/bin/env bash
# Tear down Boulder deployment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

NAMESPACE="${NAMESPACE:-boulder}"
DELETE_NAMESPACE="${DELETE_NAMESPACE:-false}"
DELETE_CLUSTER="${DELETE_CLUSTER:-false}"
CLUSTER_NAME="${CLUSTER_NAME:-boulder-dev}"

echo "==> Tearing down Boulder deployment..."

# Delete Boulder resources
echo "  Deleting Boulder resources..."
for overlay in dev dev-vitess staging prod; do
    if [ -d "$ROOT_DIR/k8s/overlays/$overlay" ]; then
        kubectl delete -k "$ROOT_DIR/k8s/overlays/$overlay" --ignore-not-found || true
    fi
done

# Delete Helm releases
echo "  Deleting Helm releases..."
helm uninstall redis -n "$NAMESPACE" 2>/dev/null || true
helm uninstall vitess -n "$NAMESPACE" 2>/dev/null || true

# Delete namespace if requested
if [ "$DELETE_NAMESPACE" = "true" ]; then
    echo "  Deleting namespace $NAMESPACE..."
    kubectl delete namespace "$NAMESPACE" --ignore-not-found
fi

# Delete kind cluster if requested
if [ "$DELETE_CLUSTER" = "true" ]; then
    echo "  Deleting kind cluster $CLUSTER_NAME..."
    kind delete cluster --name "$CLUSTER_NAME"
fi

echo "==> Teardown complete"
