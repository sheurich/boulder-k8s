#!/bin/bash

set -euo pipefail

CLUSTER_NAME="boulder-dev-ci"

echo "Deleting KinD cluster: ${CLUSTER_NAME}"

if ! command -v kind &> /dev/null; then
    echo "Error: kind is not installed. Please install kind first."
    echo "Visit: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster ${CLUSTER_NAME} does not exist. Nothing to delete."
    exit 0
fi

echo "Deleting cluster ${CLUSTER_NAME}..."
kind delete cluster --name "${CLUSTER_NAME}"

echo "✅ Cluster ${CLUSTER_NAME} has been deleted successfully!"
echo "To create a new cluster, run: ./create-cluster.sh"
