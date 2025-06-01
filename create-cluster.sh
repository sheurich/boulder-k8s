#!/bin/bash

set -euo pipefail

CLUSTER_NAME="boulder-dev-ci"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CONFIG="${SCRIPT_DIR}/kind-config.yaml"

echo "Creating KinD cluster: ${CLUSTER_NAME}"

if ! command -v kind &> /dev/null; then
    echo "Error: kind is not installed. Please install kind first."
    echo "Visit: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed. Please install kubectl first."
    echo "Visit: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "Error: docker is not installed or not running. Please install and start Docker first."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running. Please start Docker first."
    exit 1
fi

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster ${CLUSTER_NAME} already exists. Deleting it first..."
    kind delete cluster --name "${CLUSTER_NAME}"
fi

echo "Creating cluster with config: ${KIND_CONFIG}"
kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"

echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "Verifying cluster status..."
echo "Cluster info:"
kubectl cluster-info

echo ""
echo "Node status:"
kubectl get nodes -o wide

echo ""
echo "System pods status:"
kubectl get pods -n kube-system

echo ""
echo "✅ Cluster ${CLUSTER_NAME} is ready!"
echo "To use this cluster, run: kubectl config use-context kind-${CLUSTER_NAME}"
echo "To delete this cluster, run: ./delete-cluster.sh"
