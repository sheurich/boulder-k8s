#!/usr/bin/env bash
set -euo pipefail

if ! rg -n "for attempt in \\$\\(seq" k8s/overlays/dev-vitess/patches/db-migrate.yaml >/dev/null; then
  echo "FAIL: db-migrate lacks retry loop for Vitess readiness"
  exit 1
fi

echo "PASS: db-migrate includes retry loop for Vitess readiness"
