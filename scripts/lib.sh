#!/usr/bin/env bash
# Shared functions for Boulder scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $*"; }
log_warn() { echo -e "${YELLOW}==>${NC} $*"; }
log_error() { echo -e "${RED}==>${NC} $*"; }
log_ok() { echo -e "  ${GREEN}✓${NC} $*"; }
log_fail() { echo -e "  ${RED}✗${NC} $*"; }

# Context-efficient wrapper: show ✓ on success, full output on failure
# Usage: run_silent "description" command [args...]
run_silent() {
    local desc="$1"
    shift
    local tmpfile
    tmpfile=$(mktemp)
    if "$@" > "$tmpfile" 2>&1; then
        log_ok "$desc"
        rm -f "$tmpfile"
        return 0
    else
        local exit_code=$?
        log_fail "$desc"
        cat "$tmpfile"
        rm -f "$tmpfile"
        return $exit_code
    fi
}
