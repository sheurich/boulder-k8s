#!/usr/bin/env bash
# Validate Kubernetes manifests using kubeconform
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Validating Kubernetes manifests..."

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

# Validate Helm values files
echo "==> Validating Helm values files..."
for values_dir in redis; do
    values_path="$ROOT_DIR/helm/$values_dir"
    if [ -d "$values_path" ]; then
        echo "  ✓ $values_dir values present"
    fi
done

echo "==> All manifests validated successfully"
