#!/usr/bin/env bash
# Wait for all Boulder services to be ready
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

NAMESPACE="${NAMESPACE:-boulder}"
TIMEOUT="${TIMEOUT:-600s}"

log_info "Waiting for Boulder services..."

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
        run_silent "$deploy ready" kubectl rollout status deployment/"$deploy" -n "$NAMESPACE" --timeout="$TIMEOUT"
    fi
done

# Check pod health (allow observer to be unhealthy)
log_info "Checking pod health..."
RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "1/1.*Running" || echo "0")

if [ "$RUNNING" -lt 15 ]; then
    log_fail "Expected 15+ pods, found $RUNNING"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

log_ok "$RUNNING pods running"
log_info "Boulder services are ready"
