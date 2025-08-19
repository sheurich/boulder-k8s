#!/bin/bash
# Boulder Kubernetes Deployment Status Script
# Shows comprehensive deployment status with health verification

set -euo pipefail

echo "=== Cluster Status ==="
kubectl cluster-info || echo "No cluster available"

echo ""
echo "=== Boulder Namespace Pods ==="
kubectl get pods -n boulder -o wide || echo "Boulder namespace not found"

echo ""
echo "=== Boulder Services ==="
kubectl get services -n boulder || echo "Boulder namespace not found"

echo ""
echo "=== Certificate Status ==="
kubectl get certificates -n boulder -o custom-columns="NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,SECRET:.spec.secretName,AGE:.metadata.creationTimestamp" 2>/dev/null || echo "No certificates found"

echo ""
echo "=== cert-manager Status ==="
kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager not found"

echo ""
echo "=== Service Health Summary ==="
if kubectl get pods -n boulder --no-headers 2>/dev/null | while read -r name ready status _ _ _; do
    if [ "$status" = "Running" ] && [ "${ready%/*}" = "${ready#*/}" ]; then
        echo "✅ $name - Ready"
    elif [ "$status" = "Running" ]; then
        echo "⚠️  $name - Running but not ready ($ready)"
    elif [ "$status" = "Completed" ]; then
        echo "✅ $name - Completed"
    else
        echo "❌ $name - $status ($ready)"
    fi
done; then
    :
else
    echo "Boulder namespace not found"
fi

echo ""
echo "=== Recent Pod Events (Errors/Warnings) ==="
kubectl get events -n boulder --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "No recent events or Boulder namespace not found"

echo ""
echo "💡 TIP: For detailed service logs, use: kubectl logs <pod-name> -n boulder"
echo "💡 TIP: For service-specific health, check logs for 'SERVING' status"