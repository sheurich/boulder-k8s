#!/usr/bin/env bash
set -euo pipefail

kubectl kustomize k8s/overlays/dev >/dev/null
kubectl kustomize k8s/overlays/dev-vitess >/dev/null

echo "PASS: kubectl kustomize works without load-restrictor"
