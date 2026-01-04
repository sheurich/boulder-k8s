#!/usr/bin/env bash
set -euo pipefail

SCRIPT="scripts/test-issuance.sh"

for rva in boulder-rva1 boulder-rva2 boulder-rva3; do
  if ! rg -n --fixed-strings "fetch_required_logs \"${rva}\"" "$SCRIPT" >/dev/null; then
    echo "FAIL: $SCRIPT does not fetch logs for ${rva}"
    exit 1
  fi
done

for rva in boulder-rva1 boulder-rva2 boulder-rva3; do
  if ! rg -n --fixed-strings "Validation result' audit event in ${rva}" "$SCRIPT" >/dev/null; then
    echo "FAIL: $SCRIPT does not assert Validation result audit event for ${rva}"
    exit 1
  fi

done

echo "PASS: $SCRIPT asserts RVA validation audit events"
