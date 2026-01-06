#!/usr/bin/env bash
# Tear down Boulder deployment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

NAMESPACE="${NAMESPACE:-boulder}"
DELETE_NAMESPACE="${DELETE_NAMESPACE:-false}"
DELETE_CLUSTER="${DELETE_CLUSTER:-false}"
CLUSTER_NAME="${CLUSTER_NAME:-boulder-dev}"

# Check if namespace exists
namespace_exists() {
    kubectl get namespace "$NAMESPACE" &>/dev/null
}

# Check if cert-manager CRDs exist (needed for kustomize delete)
cert_manager_crds_exist() {
    kubectl get crd certificates.cert-manager.io &>/dev/null
}

echo "==> Tearing down Boulder deployment..."

# Delete Boulder resources
echo "  Deleting Boulder resources..."
if namespace_exists && cert_manager_crds_exist; then
    for overlay in dev dev-vitess staging prod; do
        if [ -d "$ROOT_DIR/k8s/overlays/$overlay" ]; then
            timeout 60 kubectl delete -k "$ROOT_DIR/k8s/overlays/$overlay" --ignore-not-found 2>/dev/null || true
        fi
    done
elif namespace_exists; then
    # CRDs missing but namespace exists, just delete namespace
    kubectl delete namespace "$NAMESPACE" --ignore-not-found 2>/dev/null || true
fi

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
