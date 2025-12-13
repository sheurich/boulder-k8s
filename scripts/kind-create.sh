#!/usr/bin/env bash
# Create a kind cluster for Boulder development
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="${CLUSTER_NAME:-boulder-dev}"

echo "==> Creating kind cluster: $CLUSTER_NAME"

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster $CLUSTER_NAME already exists"
    kubectl cluster-info --context "kind-${CLUSTER_NAME}"
    exit 0
fi

# Create kind cluster with custom config
cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      # ACME HTTP
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      # ACME HTTPS
      - containerPort: 443
        hostPort: 443
        protocol: TCP
      # WFE2 HTTP
      - containerPort: 30001
        hostPort: 4001
        protocol: TCP
      # WFE2 HTTPS
      - containerPort: 30431
        hostPort: 4431
        protocol: TCP
  - role: worker
  - role: worker
EOF

echo "==> Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "==> Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s

echo "==> Kind cluster $CLUSTER_NAME is ready"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
