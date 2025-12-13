#!/usr/bin/env bash
# Wait for all Boulder services to be ready
set -euo pipefail

NAMESPACE="${NAMESPACE:-boulder}"
TIMEOUT="${TIMEOUT:-300s}"

echo "==> Waiting for Boulder services to be ready..."

# Wait for all deployments
echo "  Waiting for deployments..."
kubectl wait --for=condition=Available deployment --all \
    -n "$NAMESPACE" \
    --timeout="$TIMEOUT"

# Wait for specific critical services
SERVICES=(
    "boulder-wfe2"
    "boulder-ra"
    "boulder-sa"
    "boulder-ca"
    "boulder-va"
)

for svc in "${SERVICES[@]}"; do
    echo "  Checking $svc..."
    kubectl rollout status deployment/"$svc" -n "$NAMESPACE" --timeout="$TIMEOUT"
done

# Check pod health
echo "==> Checking pod health..."
UNHEALTHY=$(kubectl get pods -n "$NAMESPACE" \
    --field-selector=status.phase!=Running,status.phase!=Succeeded \
    -o name 2>/dev/null | wc -l)

if [ "$UNHEALTHY" -gt 0 ]; then
    echo "  ⚠ Found $UNHEALTHY unhealthy pods:"
    kubectl get pods -n "$NAMESPACE" \
        --field-selector=status.phase!=Running,status.phase!=Succeeded
    exit 1
fi

echo "==> All Boulder services are ready"

# Print service endpoints
echo ""
echo "Service endpoints:"
kubectl get svc -n "$NAMESPACE" -o wide
