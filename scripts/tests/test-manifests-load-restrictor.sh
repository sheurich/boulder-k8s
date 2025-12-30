#!/usr/bin/env bash
set -euo pipefail

if rg -n -U --multiline-dotall "kubectl kustomize.*--load-restrictor LoadRestrictionsNone" \
    scripts/test.sh >/dev/null; then
  echo "PASS: test.sh uses load-restrictor for kustomize"
  exit 0
fi

echo "FAIL: test.sh missing --load-restrictor LoadRestrictionsNone for kustomize"
exit 1
