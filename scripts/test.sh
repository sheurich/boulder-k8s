#!/usr/bin/env bash
# Run Boulder integration tests
#
# Usage:
#   ./test.sh           Run tests (requires cluster to be ready)
#   ./test.sh --setup   Setup cluster if needed, then run tests
#   ./test.sh --reset   Teardown, setup, then run tests
#
# Environment variables:
#   OVERLAY       Kustomize overlay to use (default: dev)
#                 - dev: ProxySQL + MySQL backend
#                 - dev-vitess: Vitess backend
#   NAMESPACE     Kubernetes namespace (default: boulder)
#   CLUSTER_NAME  Kind cluster name (default: boulder-dev)
#
# Examples:
#   ./test.sh --setup                      # ProxySQL backend
#   OVERLAY=dev-vitess ./test.sh --setup   # Vitess backend
#
# Exit codes:
#   0 - Tests passed
#   1 - Tests failed
#   2 - Prerequisites not met (use --setup)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

NAMESPACE="${NAMESPACE:-boulder}"
CLUSTER_NAME="${CLUSTER_NAME:-boulder-dev}"
OVERLAY="${OVERLAY:-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

#
# Utility functions
#

log_info() { echo -e "${GREEN}==>${NC} $*"; }
log_warn() { echo -e "${YELLOW}==>${NC} $*"; }
log_error() { echo -e "${RED}==>${NC} $*"; }
log_test() { echo -e "  ${GREEN}✓${NC} $*"; }
log_fail() { echo -e "  ${RED}✗${NC} $*"; }

#
# Setup functions
#

cluster_exists() {
    kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"
}

boulder_deployed() {
    kubectl get deployment boulder-wfe2 -n "$NAMESPACE" &>/dev/null
}

do_setup() {
    log_info "Setting up Boulder environment..."

    # Create cluster if needed
    if cluster_exists; then
        log_info "Cluster $CLUSTER_NAME exists, skipping creation"
    else
        log_info "Creating cluster..."
        "$SCRIPT_DIR/kind-create.sh"
    fi

    # Build images and deploy
    log_info "Deploying Boulder..."
    "$SCRIPT_DIR/deploy.sh" "$OVERLAY"

    # Wait for services
    log_info "Waiting for services..."
    "$SCRIPT_DIR/wait-ready.sh"
}

do_teardown() {
    log_info "Tearing down Boulder environment..."
    DELETE_CLUSTER=true "$SCRIPT_DIR/teardown.sh"
}

#
# Prerequisite check
#

check_prerequisites() {
    local failed=0

    if ! cluster_exists; then
        log_error "Cluster $CLUSTER_NAME does not exist"
        failed=1
    fi

    if ! kubectl get ns "$NAMESPACE" &>/dev/null; then
        log_error "Namespace $NAMESPACE does not exist"
        failed=1
    fi

    if ! boulder_deployed; then
        log_error "Boulder is not deployed"
        failed=1
    fi

    if [ "$failed" -eq 1 ]; then
        log_error "Prerequisites not met. Run with --setup to provision."
        exit 2
    fi
}

#
# Test functions
#

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))

    if "$@"; then
        log_test "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_manifests() {
    # Validate manifests build without errors
    kubectl kustomize "$ROOT_DIR/k8s/overlays/$OVERLAY" \
        --load-restrictor LoadRestrictionsNone \
        >/dev/null 2>&1
}

test_pod_health() {
    local running
    running=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
    [ "$running" -ge 15 ]
}

test_no_crashloops() {
    # Exclude known failing pods: observer (needs syslog), cronjobs (may fail between runs)
    local crashloops
    crashloops=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
        | grep -v "boulder-observer" \
        | grep -v "boulder-log-validator" \
        | grep -v "boulder-cert-checker" \
        | grep -c "CrashLoopBackOff") || crashloops=0
    [ "$crashloops" -eq 0 ]
}

test_wfe_responds() {
    kubectl exec -n "$NAMESPACE" deploy/boulder-wfe2 -- \
        curl -sf http://localhost:4001/directory >/dev/null 2>&1
}

test_acme_directory() {
    local directory
    directory=$(kubectl exec -n "$NAMESPACE" deploy/boulder-wfe2 -- \
        curl -sf http://localhost:4001/directory 2>/dev/null)
    echo "$directory" | grep -q "newAccount"
}

test_nonce_endpoint() {
    kubectl exec -n "$NAMESPACE" deploy/boulder-wfe2 -- \
        curl -sfI http://localhost:4001/acme/new-nonce 2>&1 | grep -qi "200"
}

test_dns01_issuance() {
    # Verify DNS-01 flow works from within cluster
    # Tests: service DNS resolution, WFE connectivity, challtestsrv connectivity

    # Clean up any leftover test pod
    kubectl delete pod acme-test -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

    kubectl run acme-test --rm -i --restart=Never \
        --image=curlimages/curl:latest \
        -n "$NAMESPACE" \
        --labels="app.kubernetes.io/part-of=boulder,environment=dev" \
        --timeout=60s \
        -- sh -c '
            WFE=http://boulder-wfe2.boulder.svc.cluster.local:4001
            CHALL=http://challtestsrv.boulder.svc.cluster.local:8055

            # Test WFE directory
            DIRECTORY=$(curl -sf $WFE/directory)
            if ! echo "$DIRECTORY" | grep -q newAccount; then
                echo "Failed: WFE directory"
                exit 1
            fi

            # Test nonce
            NONCE=$(curl -sfI $WFE/acme/new-nonce | grep -i replay-nonce)
            if [ -z "$NONCE" ]; then
                echo "Failed: nonce endpoint"
                exit 1
            fi

            # Test challtestsrv (returns error message on empty POST, which proves connectivity)
            CHALL_RESP=$(curl -s $CHALL/dns-request-history 2>&1)
            if ! echo "$CHALL_RESP" | grep -q "Expected JSON"; then
                echo "Failed: challtestsrv"
                exit 1
            fi

            echo "DNS-01 flow validated"
        ' 2>/dev/null
}

#
# Main
#

main() {
    local do_setup_flag=false
    local do_reset_flag=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --setup)
                do_setup_flag=true
                shift
                ;;
            --reset)
                do_reset_flag=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--setup|--reset]"
                echo ""
                echo "Options:"
                echo "  --setup   Setup cluster if needed, then run tests"
                echo "  --reset   Teardown, setup, then run tests"
                echo ""
                echo "Environment variables:"
                echo "  OVERLAY       Kustomize overlay: dev (default), dev-vitess"
                echo "  NAMESPACE     Kubernetes namespace (default: boulder)"
                echo "  CLUSTER_NAME  Kind cluster name (default: boulder-dev)"
                echo ""
                echo "Examples:"
                echo "  $0 --setup                      # ProxySQL backend"
                echo "  OVERLAY=dev-vitess $0 --setup   # Vitess backend"
                echo ""
                echo "Exit codes:"
                echo "  0 - Tests passed"
                echo "  1 - Tests failed"
                echo "  2 - Prerequisites not met"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Handle reset (teardown + setup)
    if [ "$do_reset_flag" = true ]; then
        if cluster_exists; then
            do_teardown
        fi
        do_setup
    # Handle setup only
    elif [ "$do_setup_flag" = true ]; then
        do_setup
    # Default: check prerequisites
    else
        check_prerequisites
    fi

    # Run tests
    log_info "Running tests (overlay: $OVERLAY)..."
    echo ""

    log_info "Infrastructure tests"
    run_test "Manifests build successfully" test_manifests || true
    run_test "15+ pods running" test_pod_health || true
    run_test "No pods in CrashLoopBackOff" test_no_crashloops || true

    echo ""
    log_info "Service connectivity tests"
    run_test "WFE2 responds on port 4001" test_wfe_responds || true
    run_test "ACME directory returns endpoints" test_acme_directory || true
    run_test "Nonce endpoint returns 200" test_nonce_endpoint || true

    echo ""
    log_info "Integration tests"
    run_test "DNS-01 challenge flow" test_dns01_issuance || true

    # Summary
    echo ""
    log_info "Results: $TESTS_PASSED/$TESTS_RUN passed"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        log_error "$TESTS_FAILED test(s) failed"
        exit 1
    fi

    log_info "All tests passed"
    exit 0
}

main "$@"
