#!/usr/bin/env bash
# Wait for all Boulder services to be ready
set -euo pipefail

NAMESPACE="${NAMESPACE:-boulder}"
TIMEOUT="${TIMEOUT:-600s}"

echo "==> Waiting for Boulder services to be ready..."

# Wait for critical deployments (excludes observer which needs syslog sidecar)
DEPLOYMENTS=(
    "boulder-wfe2"
    "boulder-ra"
    "boulder-sa"
    "boulder-ca"
    "boulder-va"
    "boulder-rva1"
    "boulder-rva2"
    "boulder-rva3"
    "boulder-publisher"
    "boulder-nonce-a"
    "boulder-nonce-b"
    "mysql"
    "proxysql"
    "vitess"
)

for deploy in "${DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deploy" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "  Waiting for $deploy..."
        kubectl rollout status deployment/"$deploy" -n "$NAMESPACE" --timeout="$TIMEOUT"
    else
        # Only log if it's one of the database components, as one or the other is expected
        if [[ "$deploy" =~ ^(mysql|proxysql|vitess)$ ]]; then
             echo "  Skipping $deploy (not found)"
        fi
    fi
done

# Check pod health (allow observer to be unhealthy)
echo "==> Checking pod health..."
RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "1/1.*Running" || echo "0")
echo "  $RUNNING pods running"

if [ "$RUNNING" -lt 15 ]; then
    echo "  ⚠ Expected at least 15 running pods, found $RUNNING"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

echo "==> Boulder services are ready"

# Print service endpoints
echo ""
echo "Service endpoints:"
kubectl get svc -n "$NAMESPACE" -o wide
