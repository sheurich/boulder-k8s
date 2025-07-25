#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# Create a Kubernetes cluster using kind.
#
# This script will:
# 1. Create a kind cluster with a specific name.

CLUSTER_NAME="boulder-k8s"

main() {
  echo "Provisioning local Kubernetes cluster..."
  create_cluster
  echo "Cluster ready."
}

create_cluster() {
  if ! command -v kind &> /dev/null; then
    echo "Error: kind is not installed. See https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
  fi

  if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    return
  fi

  echo "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}"
}

main "$@"
