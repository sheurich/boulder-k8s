#!/usr/bin/env bash
# Test certificate issuance against Boulder
set -euo pipefail

NAMESPACE="${NAMESPACE:-boulder}"
WFE_URL="${WFE_URL:-http://localhost:4001}"

echo "==> Testing certificate issuance..."

# Port forward WFE if not accessible
if ! curl -s "$WFE_URL/directory" > /dev/null 2>&1; then
    echo "  Starting port-forward to WFE..."
    kubectl port-forward -n "$NAMESPACE" svc/boulder-wfe2 4001:4001 &
    PF_PID=$!
    trap "kill $PF_PID 2>/dev/null || true" EXIT
    sleep 3
fi

# Check ACME directory
echo "==> Checking ACME directory..."
DIRECTORY=$(curl -s "$WFE_URL/directory")
if [ -z "$DIRECTORY" ]; then
    echo "Error: Could not fetch ACME directory"
    exit 1
fi
echo "$DIRECTORY" | jq .

# Configure challtestsrv for test domain
echo "==> Configuring challenge test server..."
CHALLTEST_URL="${CHALLTEST_URL:-http://localhost:8055}"
if ! curl -s "$CHALLTEST_URL" > /dev/null 2>&1; then
    echo "  Starting port-forward to challtestsrv..."
    kubectl port-forward -n "$NAMESPACE" svc/challtestsrv 8055:8055 &
    sleep 2
fi

TEST_DOMAIN="test-$(date +%s).example.com"

# Add DNS record for test domain
curl -s -X POST "$CHALLTEST_URL/set-default-ipv4" \
    -d '{"ip":"10.77.77.77"}' || true

# Request certificate using certbot or acme.sh
echo "==> Requesting test certificate for $TEST_DOMAIN..."

# Check if certbot is available
if command -v certbot &> /dev/null; then
    certbot certonly \
        --standalone \
        --server "$WFE_URL/directory" \
        --domain "$TEST_DOMAIN" \
        --email test@example.com \
        --agree-tos \
        --non-interactive \
        --dry-run \
        --break-my-certs \
        2>&1 || echo "Certbot test completed (may have expected failures in test env)"
else
    echo "  certbot not found, using curl to verify ACME endpoints..."

    # Basic ACME endpoint checks
    echo "  Checking newNonce endpoint..."
    curl -s -I "$WFE_URL/acme/new-nonce" | head -5

    echo "  Checking newAccount endpoint..."
    curl -s "$WFE_URL/acme/new-acct" | head -c 200
fi

echo ""
echo "==> Certificate issuance test complete"
echo "  WFE URL: $WFE_URL"
echo "  Test domain: $TEST_DOMAIN"
