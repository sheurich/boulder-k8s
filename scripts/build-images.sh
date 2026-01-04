#!/usr/bin/env bash
# Build Boulder Docker images and load into kind cluster
#
# Usage:
#   ./build-images.sh              Build all images and load into kind
#   ./build-images.sh --load-only  Skip building, only load into kind (for CI with pre-built images)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
KIND_CLUSTER="${KIND_CLUSTER:-boulder-dev}"
LOAD_ONLY="${1:-}"
LOAD_REMOTE_IMAGES="${LOAD_REMOTE_IMAGES:-false}"

# Ensure boulder submodule is initialized
if [ ! -f "$ROOT_DIR/boulder/go.mod" ]; then
    echo "==> Boulder submodule not initialized, running git submodule update --init..."
    git -C "$ROOT_DIR" submodule update --init boulder
fi

# Build images (skip if --load-only)
if [ "$LOAD_ONLY" != "--load-only" ]; then
    echo "==> Building boulder:latest image..."
    docker build --target runtime -t boulder:latest "$ROOT_DIR"

    echo "==> Building boulder-tools:latest image..."
    docker build -t letsencrypt/boulder-tools:latest --build-arg GO_VERSION=1.25.5 "$ROOT_DIR/boulder/test/boulder-tools/"

    echo "==> Building vtcomboserver:latest image..."
    # Build locally for ARM64 support and consistency with other images
    docker build -t letsencrypt/boulder-vtcomboserver:latest \
        --build-arg VITESS_TAG=v23.0.0 \
        "$ROOT_DIR/boulder/test/vtcomboserver/"

    echo "==> Pre-pulling dependency images..."
    docker pull mysql:8.4 || true
    docker pull proxysql/proxysql:2.7.2 || true
else
    echo "==> Skipping image builds (--load-only mode)"
fi

# Load into kind if cluster exists
if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
    echo "==> Loading images into kind cluster '${KIND_CLUSTER}'..."
    kind load docker-image boulder:latest --name "$KIND_CLUSTER"
    kind load docker-image letsencrypt/boulder-tools:latest --name "$KIND_CLUSTER" || true
    kind load docker-image letsencrypt/boulder-vtcomboserver:latest --name "$KIND_CLUSTER" || true
    if [ "$LOAD_REMOTE_IMAGES" = "true" ]; then
        kind load docker-image mysql:8.4 --name "$KIND_CLUSTER" || true
        kind load docker-image proxysql/proxysql:2.7.2 --name "$KIND_CLUSTER" || true
    else
        echo "==> Skipping kind load for mysql/proxysql (set LOAD_REMOTE_IMAGES=true to force)"
    fi
else
    echo "==> Kind cluster '${KIND_CLUSTER}' not found"
    echo "    Run ./scripts/create-cluster.sh first, then re-run this script"
fi

echo "==> Done"
