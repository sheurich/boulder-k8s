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

# Check if kube-score is installed
if ! command -v kube-score &> /dev/null; then
    echo "Installing kube-score..."
    go install github.com/zegl/kube-score/cmd/kube-score@latest
fi

# Track validated overlays
validated_overlays=()

# Build all overlays and validate
for overlay in dev dev-vitess staging prod; do
    overlay_dir="$ROOT_DIR/k8s/overlays/$overlay"
    if [ -d "$overlay_dir" ]; then
        echo "==> Validating $overlay overlay..."

        # Build with kustomize
        manifests=$(kubectl kustomize "$overlay_dir" 2>/dev/null)

        # Validate with kubeconform
        echo "$manifests" | kubeconform \
            -strict \
            -ignore-missing-schemas \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            -summary \
            -
        echo "  ✓ $overlay overlay structure valid"

        # Validate with kube-score
        # Use || true to report issues without failing the build (Warning mode)
        echo "  > Scoring $overlay overlay..."
        echo "$manifests" | kube-score score - \
            --ignore-test container-image-pull-policy \
            --output-format ci || true

        validated_overlays+=("$overlay")
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

echo "==> Validated overlays: ${validated_overlays[*]}"
