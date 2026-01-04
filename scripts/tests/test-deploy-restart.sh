#!/usr/bin/env bash
set -euo pipefail

script="${1:-scripts/deploy.sh}"

if [[ ! -f "$script" ]]; then
  echo "Missing deploy script: $script" >&2
  exit 1
fi

grep -q "Restarting Boulder deployments" "$script"
grep -q "mapfile -t boulder_deploys" "$script"
grep -q "grep -v '/vitess$'" "$script"
grep -q 'rollout restart -n "$NAMESPACE" "$deploy"' "$script"
grep -q 'rollout restart -n "$NAMESPACE" deployment/challtestsrv' "$script"
