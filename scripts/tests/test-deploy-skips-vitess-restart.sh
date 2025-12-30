#!/usr/bin/env bash
set -euo pipefail

if rg -n 'rollout restart -n \"?\$NAMESPACE\"? deployment -l app.kubernetes.io/part-of=boulder' \
    scripts/deploy.sh >/dev/null; then
  echo "FAIL: deploy.sh restarts vitess via part-of=boulder selector"
  exit 1
fi

echo "PASS: deploy.sh does not restart vitess deployment"
