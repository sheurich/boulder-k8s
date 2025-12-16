#!/usr/bin/env bash
# Build Boulder-related Docker images for local development
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
KIND_CLUSTER="${KIND_CLUSTER:-boulder}"

echo "==> Building boulder-vtcomboserver image..."
docker build -t letsencrypt/boulder-vtcomboserver:latest \
    "$ROOT_DIR/boulder/test/vtcomboserver"

# Load into kind if cluster exists
if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
    echo "==> Loading image into kind cluster '${KIND_CLUSTER}'..."
    kind load docker-image letsencrypt/boulder-vtcomboserver:latest --name "$KIND_CLUSTER"
else
    echo "==> Kind cluster '${KIND_CLUSTER}' not found, skipping image load"
    echo "    Run 'kind load docker-image letsencrypt/boulder-vtcomboserver:latest --name ${KIND_CLUSTER}' after creating cluster"
fi

echo "==> Image build complete"
