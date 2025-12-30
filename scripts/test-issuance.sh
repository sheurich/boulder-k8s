#!/usr/bin/env bash
# Test certificate issuance against Boulder
#
# This script runs an ACME client (Certbot) inside the Kubernetes cluster
# to perform an end-to-end issuance test (DNS-01 challenge).
#
# It verifies:
# 1. ACME API availability (WFE)
# 2. Challenge response (VA <-> Challtestsrv)
# 3. Successful issuance
# 4. Audit log generation

set -euo pipefail

NAMESPACE="${NAMESPACE:-boulder}"
WFE_URL="${WFE_URL:-http://localhost:4001}"

echo "==> Testing certificate issuance..."

# Ensure cleanup on exit
TEST_POD="certbot-test-$(date +%s)"
cleanup() {
    echo "==> Cleaning up..."
    kubectl delete pod "$TEST_POD" -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
    # Kill background port-forwards
    jobs -p | xargs -r kill
}
trap cleanup EXIT

# 1. Start Certbot Pod
# ---------------------------------------------------------------------
echo "==> Starting Certbot pod..."
kubectl run "$TEST_POD" \
    --image=certbot/certbot:latest \
    -n "$NAMESPACE" \
    --restart=Never \
    --command -- sleep 300

echo "  Waiting for Certbot pod to be ready..."
kubectl wait --for=condition=Ready pod/"$TEST_POD" -n "$NAMESPACE" --timeout=60s >/dev/null

# 2. Configure DNS
# ---------------------------------------------------------------------
TEST_DOMAIN="test-$(date +%s).example.com"
echo "==> Configuring DNS for $TEST_DOMAIN"

kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c '
cat > /tmp/auth-hook.sh <<'"'"'EOF'"'"'
#!/bin/sh
set -eu
CHALLTEST_URL="http://challtestsrv.boulder.svc.cluster.local:8055"
HOST="_acme-challenge.${CERTBOT_DOMAIN}."
VALUE="${CERTBOT_VALIDATION}"
export CHALLTEST_URL HOST VALUE
PYTHON_BIN="python3"
command -v "${PYTHON_BIN}" >/dev/null 2>&1 || PYTHON_BIN="python"
"${PYTHON_BIN}" - <<PY
import json
import os
import urllib.request

url = os.environ["CHALLTEST_URL"] + "/set-txt"
payload = {
    "host": os.environ["HOST"],
    "value": os.environ["VALUE"],
}
data = json.dumps(payload).encode()
req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
urllib.request.urlopen(req).read()
PY
EOF
chmod +x /tmp/auth-hook.sh

cat > /tmp/cleanup-hook.sh <<'"'"'EOF'"'"'
#!/bin/sh
set -eu
CHALLTEST_URL="http://challtestsrv.boulder.svc.cluster.local:8055"
HOST="_acme-challenge.${CERTBOT_DOMAIN}."
export CHALLTEST_URL HOST
PYTHON_BIN="python3"
command -v "${PYTHON_BIN}" >/dev/null 2>&1 || PYTHON_BIN="python"
"${PYTHON_BIN}" - <<PY
import json
import os
import urllib.request

url = os.environ["CHALLTEST_URL"] + "/clear-txt"
payload = {
    "host": os.environ["HOST"],
}
data = json.dumps(payload).encode()
req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
urllib.request.urlopen(req).read()
PY
EOF
chmod +x /tmp/cleanup-hook.sh
'

# 3. Request Certificate
# ---------------------------------------------------------------------
echo "==> Requesting certificate..."

# We use the internal WFE service name since we are running inside the cluster
INTERNAL_WFE="http://boulder-wfe2:4001/directory"

kubectl exec "$TEST_POD" -n "$NAMESPACE" -- sh -c '
FLAG=""
if certbot --help 2>/dev/null | grep -q -- "--manual-public-ip-logging-ok"; then
  FLAG="--manual-public-ip-logging-ok"
fi

certbot certonly \
  --manual \
  --non-interactive \
  --agree-tos \
  --email "test@'"$TEST_DOMAIN"'" \
  --server "'"$INTERNAL_WFE"'" \
  --domain "'"$TEST_DOMAIN"'" \
  --no-eff-email \
  --break-my-certs \
  --preferred-challenges dns \
  --manual-auth-hook /tmp/auth-hook.sh \
  --manual-cleanup-hook /tmp/cleanup-hook.sh \
  $FLAG \
  --verbose
'

echo ""
echo "==> Certificate issuance successful"

# 5. Verify Audit Logs
# ---------------------------------------------------------------------
echo "==> Verifying Audit Logs..."
# Fetch logs from all Boulder components (humanlog aggregates them in dev)
# We look for the logs in the last 2 minutes to catch this run
# Pull only the relevant component logs to avoid failures from unrelated pods.
LOGS_RA=$(kubectl logs -n "$NAMESPACE" deploy/boulder-ra --tail=500 2>/dev/null || true)
LOGS_VA=$(kubectl logs -n "$NAMESPACE" deploy/boulder-va --tail=500 2>/dev/null || true)
LOGS="${LOGS_RA}"$'\n'"${LOGS_VA}"

# Check for successful issuance event (from RA)
if echo "$LOGS" | grep -q "\[AUDIT\] Certificate request - successful"; then
    echo "PASS: Found 'Certificate request - successful' audit event."
else
    echo "FAIL: Missing 'Certificate request - successful' audit event."
    echo "Recent logs:"
    echo "$LOGS" | tail -n 20
    exit 1
fi

# Check for CAA validation (from VA)
if echo "$LOGS" | grep -q "\[AUDIT\] Checked CAA records"; then
    echo "PASS: Found 'Checked CAA records' audit event."
else
    echo "FAIL: Missing 'Checked CAA records' audit event."
    exit 1
fi
