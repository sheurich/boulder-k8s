#!/bin/bash
# Boulder Kubernetes Deployment Script
# Deploys Boulder ACME CA to a Kubernetes cluster with proper service ordering
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
TIMEOUT="300s"

echo -e "${BLUE}=== Boulder Kubernetes Deployment ===${NC}"
echo -e "${YELLOW}NOTE: OCSP services are EXCLUDED (deprecated functionality)${NC}"
echo

# Function to wait for deployments to be ready
wait_for_deployment() {
    local deployment=$1
    echo -e "${BLUE}Waiting for deployment/$deployment to be ready...${NC}"
    kubectl wait --for=condition=available \
        deployment/"$deployment" \
        -n $NAMESPACE \
        --timeout=$TIMEOUT
}

# Function to wait for statefulsets to be ready
wait_for_statefulset() {
    local statefulset=$1
    echo -e "${BLUE}Waiting for statefulset/$statefulset to be ready...${NC}"
    kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
        statefulset/"$statefulset" \
        -n $NAMESPACE \
        --timeout=$TIMEOUT
}

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
        exit 1
    fi
}

# Main deployment function
main() {
    echo -e "${BLUE}Starting Boulder deployment...${NC}"
    
    # Prerequisite checks
    check_kubectl
    check_cluster
    
    echo -e "${GREEN}✓ Prerequisites validated${NC}"
    
    # Phase 1: Create namespace and RBAC
    echo -e "${BLUE}Phase 1: Creating namespace and RBAC...${NC}"
    kubectl apply -f k8s/namespaces/boulder-namespace.yaml
    echo -e "${GREEN}✓ Namespace and RBAC created${NC}"
    
    # Phase 2: Deploy secrets (must be first)
    echo -e "${BLUE}Phase 2: Creating secrets...${NC}"
    kubectl apply -f k8s/secrets/
    echo -e "${GREEN}✓ Secrets created${NC}"
    
    # Phase 3: Deploy infrastructure services
    echo -e "${BLUE}Phase 3: Deploying infrastructure services...${NC}"
    
    # MariaDB first
    kubectl apply -f k8s/deployments/infrastructure/mariadb.yaml
    kubectl apply -f k8s/services/infrastructure/mariadb-service.yaml
    wait_for_statefulset "mariadb"
    echo -e "${GREEN}✓ MariaDB deployed${NC}"
    
    # Redis instances
    kubectl apply -f k8s/deployments/infrastructure/redis.yaml
    kubectl apply -f k8s/services/infrastructure/redis-service.yaml
    wait_for_statefulset "redis-0"
    wait_for_statefulset "redis-1"
    echo -e "${GREEN}✓ Redis deployed${NC}"
    
    # ProxySQL (depends on MariaDB)
    kubectl apply -f k8s/deployments/infrastructure/proxysql.yaml
    kubectl apply -f k8s/services/infrastructure/proxysql-service.yaml
    wait_for_deployment "proxysql"
    echo -e "${GREEN}✓ ProxySQL deployed${NC}"
    
    # Phase 4: Deploy foundation Boulder services
    echo -e "${BLUE}Phase 4: Deploying foundation services...${NC}"
    
    # Storage Authority (depends on ProxySQL)
    kubectl apply -f k8s/deployments/boulder/sa.yaml
    wait_for_deployment "boulder-sa"
    echo -e "${GREEN}✓ Storage Authority deployed${NC}"
    
    # Publisher (no dependencies)
    kubectl apply -f k8s/deployments/boulder/publisher.yaml
    wait_for_deployment "boulder-publisher"
    echo -e "${GREEN}✓ Publisher deployed${NC}"
    
    # Phase 5: Deploy validation services
    echo -e "${BLUE}Phase 5: Deploying validation services...${NC}"
    
    # Remote VAs (no dependencies) - would be deployed here
    # For now, using note that they are part of main VA config
    
    # Validation Authority (depends on SA and Remote VAs)
    kubectl apply -f k8s/deployments/boulder/va.yaml
    wait_for_deployment "boulder-va"
    echo -e "${GREEN}✓ Validation Authority deployed${NC}"
    
    # Phase 6: Deploy certificate services
    echo -e "${BLUE}Phase 6: Deploying certificate services...${NC}"
    
    # Certificate Authority (depends on SA)
    kubectl apply -f k8s/deployments/boulder/ca.yaml
    wait_for_deployment "boulder-ca"
    echo -e "${GREEN}✓ Certificate Authority deployed${NC}"
    
    # Phase 7: Deploy registration services
    echo -e "${BLUE}Phase 7: Deploying registration services...${NC}"
    
    # Registration Authority (depends on SA, CA, VA, Publisher)
    kubectl apply -f k8s/deployments/boulder/ra.yaml
    wait_for_deployment "boulder-ra"
    echo -e "${GREEN}✓ Registration Authority deployed${NC}"
    
    # Phase 8: Deploy web services
    echo -e "${BLUE}Phase 8: Deploying web services...${NC}"
    
    # Web Front End (depends on RA, SA)
    kubectl apply -f k8s/deployments/boulder/wfe2.yaml
    wait_for_deployment "boulder-wfe2"
    echo -e "${GREEN}✓ Web Front End deployed${NC}"
    
    # Final validation
    echo -e "${BLUE}Performing final validation...${NC}"
    
    # Check all pods are running
    echo "Pod status:"
    kubectl get pods -n $NAMESPACE
    
    # Check services
    echo -e "\nService status:"
    kubectl get services -n $NAMESPACE
    
    echo -e "\n${GREEN}=== Boulder Deployment Complete ===${NC}"
    echo -e "${GREEN}✓ All services deployed successfully${NC}"
    echo -e "${YELLOW}✓ OCSP services excluded as intended${NC}"
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Test ACME endpoint: curl -k http://localhost:4001/directory"
    echo "2. Run integration tests: ./k8s/scripts/test.sh"
    echo "3. Monitor logs: kubectl logs -f deployment/boulder-wfe2 -n boulder"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Boulder Kubernetes Deployment Script"
        echo
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --dry-run     Show what would be deployed without applying"
        echo
        echo "This script deploys Boulder ACME CA services to Kubernetes"
        echo "OCSP services are excluded (deprecated functionality)"
        exit 0
        ;;
    --dry-run)
        echo -e "${YELLOW}Dry run mode - showing deployment order:${NC}"
        echo "1. Namespace and RBAC"
        echo "2. Secrets"
        echo "3. Infrastructure: MariaDB → Redis → ProxySQL"
        echo "4. Foundation: SA → Publisher"
        echo "5. Validation: VA"
        echo "6. Certificate: CA"
        echo "7. Registration: RA"
        echo "8. Web: WFE2"
        echo
        echo -e "${YELLOW}OCSP services are EXCLUDED${NC}"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use --help for usage information"
        exit 1
        ;;
esac