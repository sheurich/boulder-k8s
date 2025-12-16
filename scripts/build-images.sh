#!/usr/bin/env bash
# Build Boulder-related Docker images for local development
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
KIND_CLUSTER="${KIND_CLUSTER:-boulder}"

echo "==> Boulder K8s uses official images:"
echo "    - mysql:8.4 (database)"
echo "    - proxysql/proxysql:2.7.2 (connection pooling)"
echo "    - letsencrypt/boulder:latest (Boulder services)"
echo "    - letsencrypt/boulder-tools:latest (migrations)"
echo ""
echo "==> No custom images need to be built for dev/CI deployment."
echo ""

# Pre-pull images for faster deployment if Docker is available
if command -v docker &> /dev/null; then
    echo "==> Pre-pulling images for faster deployment..."
    docker pull mysql:8.4 || true
    docker pull proxysql/proxysql:2.7.2 || true

    # Load into kind if cluster exists
    if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
        echo "==> Loading images into kind cluster '${KIND_CLUSTER}'..."
        kind load docker-image mysql:8.4 --name "$KIND_CLUSTER" || true
        kind load docker-image proxysql/proxysql:2.7.2 --name "$KIND_CLUSTER" || true
    else
        echo "==> Kind cluster '${KIND_CLUSTER}' not found, skipping image load"
        echo "    Run this script again after creating the cluster to pre-load images"
    fi
fi

echo "==> Done"
