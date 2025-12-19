#!/usr/bin/env bash
# Build Boulder Docker image and load into kind cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
KIND_CLUSTER="${KIND_CLUSTER:-boulder-dev}"

echo "==> Building boulder:latest image..."
docker build --target runtime -t boulder:latest "$ROOT_DIR"

echo "==> Pre-pulling dependency images..."
docker pull mysql:8.4 || true
docker pull proxysql/proxysql:2.7.2 || true
docker pull letsencrypt/boulder-tools:latest || true

# Load into kind if cluster exists
if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
    echo "==> Loading images into kind cluster '${KIND_CLUSTER}'..."
    kind load docker-image boulder:latest --name "$KIND_CLUSTER"
    kind load docker-image mysql:8.4 --name "$KIND_CLUSTER" || true
    kind load docker-image proxysql/proxysql:2.7.2 --name "$KIND_CLUSTER" || true
    kind load docker-image letsencrypt/boulder-tools:latest --name "$KIND_CLUSTER" || true
else
    echo "==> Kind cluster '${KIND_CLUSTER}' not found"
    echo "    Run ./scripts/kind-create.sh first, then re-run this script"
fi

echo "==> Done"
