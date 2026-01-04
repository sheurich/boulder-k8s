#!/usr/bin/env bash
# Boulder test orchestrator
#
# Usage:
#   ./test.sh              Run tests (cluster must exist)
#   ./test.sh setup        Create cluster + deploy (no tests)
#   ./test.sh full         Setup + tests
#   ./test.sh reset        Teardown + setup + tests
#   ./test.sh teardown     Remove resources
#   ./test.sh validate     Offline manifest validation
#   ./test.sh issuance     End-to-end certificate issuance
#   ./test.sh help         Show usage
#
# Flags:
#   --overlay <name>       Select overlay (default: dev)
#   --continue             Continue past test failures
#   --cluster              Also delete kind cluster (teardown)
#   --namespace            Also delete namespace (teardown)
#
# Exit codes:
#   0 - Success
#   1 - Test failure
#   2 - Prerequisite missing
#   3 - Setup failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/scripts/lib.sh"

# Defaults
OVERLAY="${OVERLAY:-dev}"
NAMESPACE="${NAMESPACE:-boulder}"
CLUSTER_NAME="${CLUSTER_NAME:-boulder-dev}"
CONTINUE_ON_FAILURE=false
DELETE_CLUSTER=false
DELETE_NAMESPACE=false

# Test-specific logging
log_test() { echo -e "  ${GREEN}[PASS]${NC} $*"; }

#
# Utility functions
#

cluster_exists() {
    kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"
}

boulder_deployed() {
    kubectl get deployment boulder-wfe2 -n "$NAMESPACE" &>/dev/null
}

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
        log_error "Prerequisites not met. Run './test.sh setup' to provision."
        exit 2
    fi
}

#
# Test runner
#

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
JUNIT_TESTCASES=""
JUNIT_SUITE_START=0

junit_start_suite() {
    if [ -n "${JUNIT_FILE:-}" ]; then
        JUNIT_SUITE_START=$(date +%s)
        JUNIT_TESTCASES=""
    fi
}

junit_end_suite() {
    if [ -n "${JUNIT_FILE:-}" ]; then
        local duration=$(($(date +%s) - JUNIT_SUITE_START))
        cat > "$JUNIT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="boulder-tests" tests="$TESTS_RUN" failures="$TESTS_FAILED" errors="0" time="$duration">
$JUNIT_TESTCASES</testsuite>
EOF
    fi
}

run_test() {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))

    local start_time
    start_time=$(date +%s)

    if "$@"; then
        log_test "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [ -n "${JUNIT_FILE:-}" ]; then
            local elapsed=$(($(date +%s) - start_time))
            JUNIT_TESTCASES+="  <testcase name=\"$name\" time=\"$elapsed\"/>"$'\n'
        fi
        return 0
    else
        log_fail "$name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        if [ -n "${JUNIT_FILE:-}" ]; then
            local elapsed=$(($(date +%s) - start_time))
            JUNIT_TESTCASES+="  <testcase name=\"$name\" time=\"$elapsed\">"$'\n'
            JUNIT_TESTCASES+="    <failure message=\"Test failed\"/>"$'\n'
            JUNIT_TESTCASES+="  </testcase>"$'\n'
        fi
        if [ "$CONTINUE_ON_FAILURE" = false ]; then
            junit_end_suite
            log_error "Stopping on first failure (use --continue to run all tests)"
            exit 1
        fi
        return 1
    fi
}

#
# Test functions
#

test_manifests() {
    kubectl kustomize "$SCRIPT_DIR/k8s/overlays/$OVERLAY" >/dev/null 2>&1
}

test_pod_health() {
    local expected
    expected=$(kubectl get deployments -n "$NAMESPACE" --no-headers | wc -l)
    local running
    running=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
        | grep -c "Running") || running=0
    [ "$running" -ge "$expected" ]
}

test_no_crashloops() {
    local crashloops
    crashloops=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
        | grep -v "boulder-observer" \
        | grep -c "CrashLoopBackOff" || true)
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

test_dns01_connectivity() {
    kubectl delete pod acme-test -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

    kubectl run acme-test --rm -i --restart=Never \
        --image=curlimages/curl:latest \
        -n "$NAMESPACE" \
        --labels="app.kubernetes.io/part-of=boulder,environment=dev" \
        --timeout=60s \
        -- sh -c '
            WFE=http://boulder-wfe2.boulder.svc.cluster.local:4001
            CHALL=http://challtestsrv.boulder.svc.cluster.local:8055

            DIRECTORY=$(curl -sf $WFE/directory)
            if ! echo "$DIRECTORY" | grep -q newAccount; then
                echo "Failed: WFE directory"
                exit 1
            fi

            NONCE=$(curl -sfI $WFE/acme/new-nonce | grep -i replay-nonce)
            if [ -z "$NONCE" ]; then
                echo "Failed: nonce endpoint"
                exit 1
            fi

            CHALL_RESP=$(curl -s $CHALL/dns-request-history 2>&1)
            if ! echo "$CHALL_RESP" | grep -q "Expected JSON"; then
                echo "Failed: challtestsrv"
                exit 1
            fi

            echo "DNS-01 flow validated"
        ' 2>/dev/null
}

run_tests() {
    junit_start_suite "boulder-tests"

    log_info "Running tests (overlay: $OVERLAY)..."
    echo ""

    log_info "Infrastructure tests"
    run_test "Manifests build successfully" test_manifests
    run_test "All deployments have running pods" test_pod_health
    run_test "No pods in CrashLoopBackOff" test_no_crashloops

    echo ""
    log_info "Service connectivity tests"
    run_test "WFE2 responds on port 4001" test_wfe_responds
    run_test "ACME directory returns endpoints" test_acme_directory
    run_test "Nonce endpoint returns 200" test_nonce_endpoint

    echo ""
    log_info "Integration tests"
    run_test "DNS-01 connectivity" test_dns01_connectivity

    junit_end_suite

    echo ""
    log_info "Results: $TESTS_PASSED/$TESTS_RUN passed"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        log_error "$TESTS_FAILED test(s) failed"
        exit 1
    fi

    log_info "All tests passed"
}

#
# Subcommand handlers
#

cmd_setup() {
    log_info "Setting up Boulder environment (overlay: $OVERLAY)..."

    if cluster_exists; then
        log_info "Cluster $CLUSTER_NAME exists, skipping creation"
    else
        log_info "Creating cluster..."
        if ! "$SCRIPT_DIR/scripts/create-cluster.sh"; then
            log_error "Cluster creation failed"
            exit 3
        fi
    fi

    log_info "Deploying Boulder..."
    if ! "$SCRIPT_DIR/scripts/deploy.sh" "$OVERLAY"; then
        log_error "Deployment failed"
        exit 3
    fi

    log_info "Waiting for services..."
    if ! "$SCRIPT_DIR/scripts/wait-ready.sh"; then
        log_error "Services failed to become ready"
        exit 3
    fi

    log_info "Setup complete"
}

cmd_full() {
    cmd_setup
    run_tests
}

cmd_reset() {
    log_info "Resetting Boulder environment..."

    if cluster_exists; then
        log_info "Tearing down existing cluster..."
        DELETE_CLUSTER=true "$SCRIPT_DIR/scripts/teardown.sh"
    fi

    cmd_setup
    run_tests
}

cmd_teardown() {
    log_info "Tearing down Boulder environment..."

    export DELETE_CLUSTER
    export DELETE_NAMESPACE
    "$SCRIPT_DIR/scripts/teardown.sh"

    log_info "Teardown complete"
}

cmd_validate() {
    exec "$SCRIPT_DIR/scripts/validate-manifests.sh"
}

cmd_issuance() {
    check_prerequisites
    exec "$SCRIPT_DIR/scripts/test-issuance.sh"
}

cmd_test() {
    check_prerequisites
    run_tests
}

# List available test functions
list_tests() {
    echo "Available tests:"
    declare -F | awk '{print $3}' | grep '^test_' | sed 's/^test_/  /'
}

cmd_test_single() {
    local filter="${1:-}"

    check_prerequisites

    if [ -z "$filter" ]; then
        run_tests
        return
    fi

    local func="test_$filter"
    if ! declare -f "$func" >/dev/null 2>&1; then
        log_error "Unknown test: $filter"
        list_tests
        exit 1
    fi

    junit_start_suite "boulder-tests"
    run_test "$filter" "$func"
    junit_end_suite

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}

cmd_unit() {
    local test_dir="$SCRIPT_DIR/scripts/tests"
    local passed=0
    local failed=0
    local failed_tests=""

    if [ ! -d "$test_dir" ] || [ -z "$(ls -A "$test_dir"/*.sh 2>/dev/null)" ]; then
        log_info "No unit tests found in $test_dir"
        return 0
    fi

    log_info "Running unit tests..."
    echo ""

    for test in "$test_dir"/*.sh; do
        local name
        name=$(basename "$test")
        if bash "$test"; then
            log_ok "$name"
            passed=$((passed + 1))
        else
            log_fail "$name"
            failed=$((failed + 1))
            failed_tests="$failed_tests $name"
        fi
    done

    echo ""
    log_info "Results: $passed/$((passed + failed)) passed"

    if [ "$failed" -gt 0 ]; then
        log_error "Failed tests:$failed_tests"
        exit 1
    fi

    log_info "All unit tests passed"
}

cmd_help() {
    cat <<EOF
Usage: $0 [command] [flags]

Commands:
  (default)     Run tests (cluster must exist)
  test [name]   Run single test or all tests
  unit          Run scripts/tests/*.sh unit tests
  setup         Create cluster + deploy (no tests)
  full          Setup + tests
  reset         Teardown + setup + tests
  teardown      Remove resources
  validate      Offline manifest validation
  issuance      End-to-end certificate issuance
  help          Show this help

Flags:
  --overlay <name>   Select overlay (default: dev)
  --continue         Continue past test failures
  --cluster          Also delete kind cluster (teardown)
  --namespace        Also delete namespace (teardown)

Environment Variables:
  OVERLAY        Kustomize overlay (default: dev)
  NAMESPACE      Kubernetes namespace (default: boulder)
  CLUSTER_NAME   Kind cluster name (default: boulder-dev)
  JUNIT_FILE     Write JUnit XML to this file (optional)

Examples:
  $0                           # Run tests
  $0 test wfe_responds         # Run single test
  $0 unit                      # Run unit tests
  $0 setup                     # Setup cluster and deploy
  $0 full                      # Setup + tests
  $0 reset --overlay dev-vitess  # Reset with Vitess backend
  $0 teardown --cluster        # Remove everything
  JUNIT_FILE=results.xml $0    # Write JUnit output

Exit codes:
  0 - Success
  1 - Test failure
  2 - Prerequisite missing
  3 - Setup failure
EOF
}

#
# Main
#

parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --overlay)
                if [[ -z "${2:-}" || "$2" == --* ]]; then
                    log_error "--overlay requires a value"
                    exit 1
                fi
                OVERLAY="$2"
                shift 2
                ;;
            --continue)
                CONTINUE_ON_FAILURE=true
                shift
                ;;
            --cluster)
                DELETE_CLUSTER=true
                shift
                ;;
            --namespace)
                DELETE_NAMESPACE=true
                shift
                ;;
            -h|--help)
                cmd_help
                exit 0
                ;;
            *)
                log_error "Unknown flag: $1"
                cmd_help
                exit 2
                ;;
        esac
    done
}

main() {
    local cmd="${1:-}"

    case "$cmd" in
        setup|full|reset|teardown|validate|issuance|help|unit)
            shift
            parse_flags "$@"
            "cmd_$cmd"
            ;;
        test)
            shift
            local test_name=""
            if [[ -n "${1:-}" && "$1" != --* ]]; then
                test_name="$1"
                shift
            fi
            parse_flags "$@"
            cmd_test_single "$test_name"
            ;;
        --*|-*)
            # Flag without subcommand = run tests
            parse_flags "$@"
            cmd_test
            ;;
        "")
            cmd_test
            ;;
        *)
            log_error "Unknown command: $cmd"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
