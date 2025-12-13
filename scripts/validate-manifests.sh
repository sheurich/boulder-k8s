#!/usr/bin/env bash
# Validate Kubernetes manifests using kubeconform
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Validating Kubernetes manifests..."

# Ensure go bin is in PATH
export PATH="$PATH:$(go env GOPATH)/bin"

# Check if kubeconform is installed
if ! command -v kubeconform &> /dev/null; then
    echo "Installing kubeconform..."
    go install github.com/yannh/kubeconform/cmd/kubeconform@latest
fi

# Build all overlays and validate
for overlay in dev staging prod; do
    echo "==> Validating $overlay overlay..."

    overlay_dir="$ROOT_DIR/k8s/overlays/$overlay"
    if [ -d "$overlay_dir" ]; then
        # Build with kustomize and validate
        kubectl kustomize "$overlay_dir" 2>/dev/null | kubeconform \
            -strict \
            -ignore-missing-schemas \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            -summary \
            -
        echo "  ✓ $overlay overlay valid"
    else
        echo "  ⚠ $overlay overlay directory not found, skipping"
    fi
done

# Validate Helm charts
echo "==> Validating Helm charts..."

for chart in softhsm-proxy; do
    chart_dir="$ROOT_DIR/helm/$chart"
    if [ -d "$chart_dir" ]; then
        echo "  Linting $chart..."
        helm lint "$chart_dir"
        echo "  ✓ $chart chart valid"
    fi
done

echo "==> All manifests validated successfully"
