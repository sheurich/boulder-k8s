#!/usr/bin/env bash
# Validate Kubernetes manifests using kubeconform
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

log_info "Validating Kubernetes manifests..."

# Check if kubeconform is installed
if ! command -v kubeconform &> /dev/null; then
    log_warn "Installing kubeconform..."
    go install github.com/yannh/kubeconform/cmd/kubeconform@latest
fi

# Check if kube-score is installed
if ! command -v kube-score &> /dev/null; then
    log_warn "Installing kube-score..."
    go install github.com/zegl/kube-score/cmd/kube-score@latest
fi

# Track validated overlays
validated_overlays=()

# Build all overlays and validate
for overlay in dev dev-vitess staging prod; do
    overlay_dir="$ROOT_DIR/k8s/overlays/$overlay"
    if [ -d "$overlay_dir" ]; then
        log_info "Validating $overlay overlay..."

        # Build with kustomize
        manifests=$(kubectl kustomize "$overlay_dir" 2>/dev/null)

        # Validate with kubeconform (summary mode - only show counts)
        if echo "$manifests" | kubeconform \
            -strict \
            -ignore-missing-schemas \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            -summary \
            - >/dev/null 2>&1; then
            log_ok "$overlay kubeconform valid"
        else
            log_fail "$overlay kubeconform failed"
            echo "$manifests" | kubeconform \
                -strict \
                -ignore-missing-schemas \
                -schema-location default \
                -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
                -summary \
                -
        fi

        # Validate with kube-score (summary mode - count by grade)
        score_output=$(echo "$manifests" | kube-score score - \
            --ignore-test container-image-pull-policy \
            --output-format ci 2>&1) || true
        critical_count=$(echo "$score_output" | grep -c "^\[CRITICAL\]" || echo "0")
        if [ "$critical_count" -eq 0 ]; then
            log_ok "$overlay kube-score passed (no critical issues)"
        else
            log_warn "$overlay kube-score: $critical_count critical issue(s)"
            echo "$score_output" | grep "^\[CRITICAL\]" || true
        fi

        validated_overlays+=("$overlay")
    fi
done

# Validate Helm values files
log_info "Validating Helm values..."
for values_dir in redis; do
    values_path="$ROOT_DIR/helm/$values_dir"
    if [ -d "$values_path" ]; then
        log_ok "$values_dir values present"
    fi
done

log_info "Validated: ${validated_overlays[*]}"
