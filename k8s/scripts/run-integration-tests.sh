#!/bin/bash
# Boulder Integration Test Execution Script
# Orchestrates integration test execution and monitoring for Boulder Kubernetes deployment
# EXCLUDES all OCSP-related tests (deprecated functionality)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="boulder"
JOB_NAME="boulder-integration-test"
TIMEOUT="1800s"  # 30 minutes
POLL_INTERVAL=10

echo -e "${BLUE}=== Boulder Integration Test Runner ===${NC}"
echo -e "${YELLOW}NOTE: OCSP tests are EXCLUDED (deprecated functionality)${NC}"
echo

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
}

# Function to check if cluster is accessible
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
        echo "Please ensure your kubeconfig is set up correctly"
        echo "For kind clusters, run: kind get kubeconfig --name boulder-k8s"
        exit 1
    fi
    
    # Check if it's a kind cluster
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ "$context" == *"kind"* ]]; then
        echo -e "${GREEN}✓ Connected to kind cluster: $context${NC}"
    else
        echo -e "${YELLOW}⚠ Connected to non-kind cluster: $context${NC}"
    fi
}

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
        echo "Please run the deployment script first: ./k8s/scripts/deploy.sh"
        exit 1
    fi
    echo -e "${GREEN}✓ Namespace '$NAMESPACE' found${NC}"
}

# Function to verify Boulder services are ready
verify_boulder_services() {
    echo -e "${BLUE}Checking Boulder service readiness...${NC}"
    
    local services=(
        "boulder-wfe2"
        "boulder-ra" 
        "boulder-sa"
        "boulder-ca"
        "boulder-va"
        "boulder-publisher"
    )
    
    for service in "${services[@]}"; do
        echo -n "Checking $service... "
        if kubectl wait --for=condition=available deployment/"$service" -n "$NAMESPACE" --timeout=30s &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            echo -e "${RED}Error: Service $service is not ready${NC}"
            echo "Run health check for more details: ./k8s/scripts/health-check.sh"
            exit 1
        fi
    done
    
    # Special check for WFE2 HTTP endpoint
    echo -n "Checking WFE2 ACME endpoint... "
    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l app=boulder-wfe2 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pod_name" ]]; then
        if kubectl exec -n "$NAMESPACE" "$pod_name" -- wget -q --spider --timeout=5 http://localhost:4001/directory &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            echo -e "${RED}Error: WFE2 ACME endpoint is not responding${NC}"
            exit 1
        fi
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}Error: No WFE2 pod found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All Boulder services are ready${NC}"
}

# Function to clean up existing test job
cleanup_existing_job() {
    if kubectl get job "$JOB_NAME" -n "$NAMESPACE" &> /dev/null; then
        echo -e "${YELLOW}Cleaning up existing test job...${NC}"
        kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found=true
        
        # Wait for cleanup to complete
        local count=0
        while kubectl get job "$JOB_NAME" -n "$NAMESPACE" &> /dev/null && [[ $count -lt 30 ]]; do
            sleep 2
            ((count++))
        done
        
        if [[ $count -ge 30 ]]; then
            echo -e "${RED}Warning: Timeout waiting for job cleanup${NC}"
        else
            echo -e "${GREEN}✓ Existing job cleaned up${NC}"
        fi
    fi
}

# Function to apply integration test job
apply_test_job() {
    echo -e "${BLUE}Starting integration test job...${NC}"
    
    if ! kubectl apply -f k8s/jobs/boulder-integration-test.yaml; then
        echo -e "${RED}Error: Failed to apply integration test job${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Integration test job created${NC}"
}

# Function to monitor job execution
monitor_job() {
    echo -e "${BLUE}Monitoring integration test execution...${NC}"
    echo "Job timeout: $TIMEOUT"
    echo "Poll interval: ${POLL_INTERVAL}s"
    echo
    
    local start_time
    start_time=$(date +%s)
    local timeout_seconds=${TIMEOUT%s}
    
    # Wait for pod to be created
    local pod_name=""
    local count=0
    while [[ -z "$pod_name" ]] && [[ $count -lt 60 ]]; do
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$pod_name" ]]; then
            echo "Waiting for test pod to be created..."
            sleep 5
            ((count++))
        fi
    done
    
    if [[ -z "$pod_name" ]]; then
        echo -e "${RED}Error: Test pod was not created within timeout${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Test pod created: $pod_name${NC}"
    
    # Monitor job status
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout_seconds ]]; then
            echo -e "${RED}Error: Integration test exceeded timeout of $TIMEOUT${NC}"
            return 1
        fi
        
        # Check job status
        local job_status
        job_status=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
        
        case "$job_status" in
            "Complete")
                echo -e "${GREEN}✓ Integration test completed successfully!${NC}"
                return 0
                ;;
            "Failed")
                echo -e "${RED}✗ Integration test failed${NC}"
                return 1
                ;;
            *)
                # Job still running, show progress
                local pod_phase
                pod_phase=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                printf "\r${BLUE}Status: %s, Pod Phase: %s, Elapsed: %ds${NC}" "$job_status" "$pod_phase" "$elapsed"
                sleep $POLL_INTERVAL
                ;;
        esac
    done
}

# Function to collect and display test results
collect_results() {
    local exit_code=$1
    echo
    echo -e "${BLUE}=== Integration Test Results ===${NC}"
    
    # Get pod name
    local pod_name
    pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pod_name" ]]; then
        echo -e "${BLUE}Pod: $pod_name${NC}"
        
        # Show pod status
        local pod_phase
        pod_phase=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo -e "${BLUE}Pod Phase: $pod_phase${NC}"
        
        # Show job status
        local job_status
        job_status=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status}' 2>/dev/null || echo "{}")
        echo -e "${BLUE}Job Status:${NC}"
        echo "$job_status" | kubectl neat 2>/dev/null || echo "$job_status"
        
        echo
        echo -e "${BLUE}=== Integration Test Logs ===${NC}"
        kubectl logs "$pod_name" -n "$NAMESPACE" --tail=100
        
        # Get full logs for debugging if test failed
        if [[ $exit_code -ne 0 ]]; then
            echo
            echo -e "${YELLOW}Full logs (for debugging):${NC}"
            kubectl logs "$pod_name" -n "$NAMESPACE"
        fi
    else
        echo -e "${RED}Error: Could not find test pod${NC}"
    fi
    
    echo
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}=== INTEGRATION TESTS PASSED ===${NC}"
        echo -e "${GREEN}✓ Boulder ACME functionality verified${NC}"
        echo -e "${GREEN}✓ OCSP tests excluded as intended${NC}"
    else
        echo -e "${RED}=== INTEGRATION TESTS FAILED ===${NC}"
        echo -e "${RED}✗ See logs above for details${NC}"
    fi
}

# Function to clean up test resources
cleanup_test_resources() {
    if [[ "${CLEANUP:-true}" == "true" ]]; then
        echo
        echo -e "${BLUE}Cleaning up test resources...${NC}"
        kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found=true
        echo -e "${GREEN}✓ Test resources cleaned up${NC}"
    else
        echo
        echo -e "${YELLOW}Skipping cleanup (CLEANUP=false)${NC}"
        echo "To clean up manually: kubectl delete job $JOB_NAME -n $NAMESPACE"
    fi
}

# Function to show usage
show_help() {
    echo "Boulder Integration Test Runner"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo "  --no-cleanup      Skip cleanup of test resources after completion"
    echo "  --timeout TIMEOUT Set test timeout (default: 1800s)"
    echo
    echo "Environment Variables:"
    echo "  CLEANUP=false     Skip cleanup (same as --no-cleanup)"
    echo
    echo "This script runs Boulder integration tests in Kubernetes"
    echo "OCSP tests are excluded (deprecated functionality)"
    echo
    echo "Prerequisites:"
    echo "  - kubectl configured and connected to cluster"
    echo "  - Boulder services deployed and running"
    echo "  - Integration test job manifest exists"
}

# Main execution function
main() {
    echo -e "${BLUE}Starting integration test execution...${NC}"
    
    # Prerequisite checks
    check_kubectl
    check_cluster
    check_namespace
    
    # Verify Boulder is ready
    verify_boulder_services
    
    # Clean up any existing test job
    cleanup_existing_job
    
    # Apply and monitor test job
    apply_test_job
    
    local test_result=0
    if ! monitor_job; then
        test_result=1
    fi
    
    # Collect and display results
    collect_results $test_result
    
    # Cleanup
    cleanup_test_resources
    
    return $test_result
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --no-cleanup)
            export CLEANUP=false
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function and preserve exit code
main
exit_code=$?

echo
if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}Integration test execution completed successfully${NC}"
else
    echo -e "${RED}Integration test execution failed${NC}"
fi

exit $exit_code