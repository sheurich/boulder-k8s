#!/usr/bin/env bash
set -euo pipefail

if ! rg -n --fixed-strings -- "--preferred-challenges dns" scripts/test-issuance.sh >/dev/null; then
  echo "FAIL: test-issuance.sh does not request DNS-01 challenges"
  exit 1
fi

if ! rg -n "/set-txt" scripts/test-issuance.sh >/dev/null; then
  echo "FAIL: test-issuance.sh does not configure DNS-01 TXT records"
  exit 1
fi

if ! rg -n "/clear-txt" scripts/test-issuance.sh >/dev/null; then
  echo "FAIL: test-issuance.sh does not clean DNS-01 TXT records"
  exit 1
fi

echo "PASS: test-issuance.sh uses DNS-01 via challtestsrv"
