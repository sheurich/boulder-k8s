#!/bin/bash
# Boulder Health Check Script
# Validates service readiness for Boulder Kubernetes deployment
# EXCLUDES all OCSP-related services (deprecated functionality)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="boulder"
TIMEOUT="30s"

echo -e "${BLUE}=== Boulder Health Check ===${NC}"
echo -e "${YELLOW}NOTE: OCSP services are EXCLUDED (deprecated functionality)${NC}"
echo

# Global health status
OVERALL_HEALTH=0

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl is not installed or not in PATH${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ kubectl is available${NC}"
    return 0
}

# Function to check if cluster is accessible
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        echo "  Please ensure your kubeconfig is set up correctly"
        return 1
    fi
    
    # Show cluster context
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Connected to cluster: $context${NC}"
    return 0
}

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${RED}✗ Namespace '$NAMESPACE' does not exist${NC}"
        echo "  Please run the deployment script first: ./k8s/scripts/deploy.sh"
        return 1
    fi
    echo -e "${GREEN}✓ Namespace '$NAMESPACE' exists${NC}"
    return 0
}

# Function to check infrastructure services
check_infrastructure() {
    echo -e "${BLUE}Checking infrastructure services...${NC}"
    local infra_health=0
    
    # MariaDB
    echo -n "  MariaDB... "
    if kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 statefulset/mariadb -n "$NAMESPACE" --timeout="$TIMEOUT" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        infra_health=1
    fi
    
    # Redis instances
    echo -n "  Redis-0... "
    if kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 statefulset/redis-0 -n "$NAMESPACE" --timeout="$TIMEOUT" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        infra_health=1
    fi
    
    echo -n "  Redis-1... "
    if kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 statefulset/redis-1 -n "$NAMESPACE" --timeout="$TIMEOUT" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        infra_health=1
    fi
    
    # ProxySQL
    echo -n "  ProxySQL... "
    if kubectl wait --for=condition=available deployment/proxysql -n "$NAMESPACE" --timeout="$TIMEOUT" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        infra_health=1
    fi
    
    if [[ $infra_health -eq 0 ]]; then
        echo -e "${GREEN}✓ Infrastructure services are healthy${NC}"
    else
        echo -e "${RED}✗ Infrastructure services have issues${NC}"
    fi
    
    return $infra_health
}

# Function to check Boulder services
check_boulder_services() {
    echo -e "${BLUE}Checking Boulder services...${NC}"
    local boulder_health=0
    
    local services=(
        "boulder-sa:Storage Authority"
        "boulder-ca:Certificate Authority"
        "boulder-ra:Registration Authority"
        "boulder-va:Validation Authority"
        "boulder-wfe2:Web Front End"
        "boulder-publisher:Publisher"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_desc <<< "$service_info"
        echo -n "  $service_desc... "
        
        if kubectl wait --for=condition=available deployment/"$service_name" -n "$NAMESPACE" --timeout="$TIMEOUT" &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            boulder_health=1
        fi
    done
    
    if [[ $boulder_health -eq 0 ]]; then
        echo -e "${GREEN}✓ Boulder services are healthy${NC}"
    else
        echo -e "${RED}✗ Boulder services have issues${NC}"
    fi
    
    return $boulder_health
}

# Function to test database connectivity
test_database_connectivity() {
    echo -e "${BLUE}Testing database connectivity...${NC}"
    
    # Get MariaDB pod
    local db_pod
    db_pod=$(kubectl get pods -n "$NAMESPACE" -l app=mariadb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$db_pod" ]]; then
        echo -e "${RED}✗ No MariaDB pod found${NC}"
        return 1
    fi
    
    echo -n "  MariaDB connectivity... "
    if kubectl exec -n "$NAMESPACE" "$db_pod" -- mysqladmin ping -h localhost --silent &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
    
    echo -n "  ProxySQL connectivity... "
    local proxysql_pod
    proxysql_pod=$(kubectl get pods -n "$NAMESPACE" -l app=proxysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$proxysql_pod" ]]; then
        if kubectl exec -n "$NAMESPACE" "$proxysql_pod" -- nc -z localhost 6033 &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ No ProxySQL pod found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Database connectivity is healthy${NC}"
    return 0
}

# Function to test Redis connectivity
test_redis_connectivity() {
    echo -e "${BLUE}Testing Redis connectivity...${NC}"
    
    # Test Redis-0
    echo -n "  Redis-0 connectivity... "
    local redis0_pod
    redis0_pod=$(kubectl get pods -n "$NAMESPACE" -l app=redis-0 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$redis0_pod" ]]; then
        if kubectl exec -n "$NAMESPACE" "$redis0_pod" -- redis-cli ping &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ No Redis-0 pod found${NC}"
        return 1
    fi
    
    # Test Redis-1
    echo -n "  Redis-1 connectivity... "
    local redis1_pod
    redis1_pod=$(kubectl get pods -n "$NAMESPACE" -l app=redis-1 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$redis1_pod" ]]; then
        if kubectl exec -n "$NAMESPACE" "$redis1_pod" -- redis-cli ping &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ No Redis-1 pod found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Redis connectivity is healthy${NC}"
    return 0
}

# Function to test ACME API endpoint
test_acme_endpoint() {
    echo -e "${BLUE}Testing ACME API endpoint...${NC}"
    
    # Get WFE2 pod
    local wfe2_pod
    wfe2_pod=$(kubectl get pods -n "$NAMESPACE" -l app=boulder-wfe2 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$wfe2_pod" ]]; then
        echo -e "${RED}✗ No WFE2 pod found${NC}"
        return 1
    fi
    
    echo -n "  ACME directory endpoint... "
    if kubectl exec -n "$NAMESPACE" "$wfe2_pod" -- wget -q --spider --timeout=5 http://localhost:4001/directory &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
    
    echo -n "  ACME directory content... "
    local directory_content
    directory_content=$(kubectl exec -n "$NAMESPACE" "$wfe2_pod" -- wget -q -O - --timeout=5 http://localhost:4001/directory 2>/dev/null || echo "")
    
    if [[ -n "$directory_content" ]] && echo "$directory_content" | grep -q "newAccount" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
    
    # Test external access if LoadBalancer service exists
    echo -n "  External ACME access... "
    local external_ip
    external_ip=$(kubectl get service boulder-wfe2 -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -z "$external_ip" ]]; then
        # Try getting NodePort or checking service type
        local service_type
        service_type=$(kubectl get service boulder-wfe2 -n "$NAMESPACE" -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
        
        if [[ "$service_type" == "LoadBalancer" ]]; then
            echo -e "${YELLOW}⚠ LoadBalancer IP pending${NC}"
        else
            echo -e "${YELLOW}⚠ No external access configured${NC}"
        fi
    else
        if curl -s --connect-timeout 5 "http://$external_ip:4001/directory" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}⚠ External IP not reachable${NC}"
        fi
    fi
    
    echo -e "${GREEN}✓ ACME API endpoint is healthy${NC}"
    return 0
}

# Function to check service logs for errors
check_service_logs() {
    echo -e "${BLUE}Checking recent service logs for errors...${NC}"
    
    local services=("boulder-wfe2" "boulder-ra" "boulder-sa" "boulder-ca" "boulder-va")
    local log_issues=0
    
    for service in "${services[@]}"; do
        echo -n "  $service logs... "
        
        # Get recent logs and check for ERROR or FATAL messages
        local error_count
        error_count=$(kubectl logs deployment/"$service" -n "$NAMESPACE" --tail=50 --since=5m 2>/dev/null | grep -c -i -E "(error|fatal|panic)" || echo "0")
        
        if [[ $error_count -gt 0 ]]; then
            echo -e "${YELLOW}⚠ $error_count error(s) found${NC}"
            log_issues=1
        else
            echo -e "${GREEN}✓${NC}"
        fi
    done
    
    if [[ $log_issues -eq 0 ]]; then
        echo -e "${GREEN}✓ No critical errors in recent logs${NC}"
    else
        echo -e "${YELLOW}⚠ Some services have recent errors (check logs for details)${NC}"
    fi
    
    return 0  # Don't fail overall health check for log warnings
}

# Function to show pod status summary
show_pod_status() {
    echo -e "${BLUE}Pod Status Summary:${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
}

# Function to show service status summary
show_service_status() {
    echo -e "${BLUE}Service Status Summary:${NC}"
    kubectl get services -n "$NAMESPACE"
    echo
}

# Function to show resource usage
show_resource_usage() {
    echo -e "${BLUE}Resource Usage Summary:${NC}"
    
    # Check if metrics server is available
    if kubectl top nodes &> /dev/null; then
        echo "Node resource usage:"
        kubectl top nodes
        echo
        echo "Pod resource usage (Boulder namespace):"
        kubectl top pods -n "$NAMESPACE" --sort-by=cpu
    else
        echo -e "${YELLOW}Metrics server not available - cannot show resource usage${NC}"
    fi
    echo
}

# Function to perform comprehensive health check
perform_health_check() {
    echo -e "${BLUE}Performing comprehensive health check...${NC}"
    echo
    
    # Basic connectivity checks
    if ! check_kubectl; then
        OVERALL_HEALTH=1
        return 1
    fi
    
    if ! check_cluster; then
        OVERALL_HEALTH=1
        return 1
    fi
    
    if ! check_namespace; then
        OVERALL_HEALTH=1
        return 1
    fi
    
    echo
    
    # Infrastructure health
    if ! check_infrastructure; then
        OVERALL_HEALTH=1
    fi
    
    echo
    
    # Boulder services health
    if ! check_boulder_services; then
        OVERALL_HEALTH=1
    fi
    
    echo
    
    # Connectivity tests
    if ! test_database_connectivity; then
        OVERALL_HEALTH=1
    fi
    
    echo
    
    if ! test_redis_connectivity; then
        OVERALL_HEALTH=1
    fi
    
    echo
    
    if ! test_acme_endpoint; then
        OVERALL_HEALTH=1
    fi
    
    echo
    
    # Check logs for issues
    check_service_logs
    
    echo
}

# Function to show usage
show_help() {
    echo "Boulder Health Check Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo "  --verbose, -v     Show detailed pod and service status"
    echo "  --resources, -r   Show resource usage information"
    echo "  --logs            Show recent logs from all services"
    echo
    echo "This script validates Boulder service readiness in Kubernetes"
    echo "OCSP services are excluded (deprecated functionality)"
    echo
    echo "Exit codes:"
    echo "  0 - All services healthy"
    echo "  1 - Some services have issues"
}

# Function to show recent logs
show_recent_logs() {
    echo -e "${BLUE}Recent logs from Boulder services:${NC}"
    echo
    
    local services=("boulder-wfe2" "boulder-ra" "boulder-sa" "boulder-ca" "boulder-va" "boulder-publisher")
    
    for service in "${services[@]}"; do
        echo -e "${BLUE}=== $service ===${NC}"
        kubectl logs deployment/"$service" -n "$NAMESPACE" --tail=20 --since=10m 2>/dev/null || echo "No logs available"
        echo
    done
}

# Main execution
main() {
    perform_health_check
    
    # Show summary based on options
    if [[ "${SHOW_VERBOSE:-false}" == "true" ]]; then
        show_pod_status
        show_service_status
    fi
    
    if [[ "${SHOW_RESOURCES:-false}" == "true" ]]; then
        show_resource_usage
    fi
    
    if [[ "${SHOW_LOGS:-false}" == "true" ]]; then
        show_recent_logs
    fi
    
    # Final health status
    echo -e "${BLUE}=== Health Check Summary ===${NC}"
    if [[ $OVERALL_HEALTH -eq 0 ]]; then
        echo -e "${GREEN}✓ All Boulder services are healthy${NC}"
        echo -e "${GREEN}✓ OCSP services excluded as intended${NC}"
        echo -e "${GREEN}✓ Ready for integration testing${NC}"
    else
        echo -e "${RED}✗ Some Boulder services have issues${NC}"
        echo -e "${YELLOW}⚠ Review the errors above and check logs${NC}"
        echo -e "${YELLOW}⚠ Run with --verbose for detailed status${NC}"
    fi
    
    return $OVERALL_HEALTH
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --verbose|-v)
            export SHOW_VERBOSE=true
            shift
            ;;
        --resources|-r)
            export SHOW_RESOURCES=true
            shift
            ;;
        --logs)
            export SHOW_LOGS=true
            shift
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
    echo -e "${GREEN}Health check completed successfully${NC}"
else
    echo -e "${RED}Health check found issues${NC}"
fi

exit $exit_code