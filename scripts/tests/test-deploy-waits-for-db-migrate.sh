#!/usr/bin/env bash
set -euo pipefail

if ! rg -n "kubectl wait --for=condition=complete job/boulder-db-migrate" scripts/deploy.sh >/dev/null; then
  echo "FAIL: deploy.sh does not wait for db-migrate job completion"
  exit 1
fi

echo "PASS: deploy.sh waits for db-migrate job completion"
