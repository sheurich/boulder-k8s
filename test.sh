#!/usr/bin/env bash
set -e

echo "Running Kubernetes smoke tests..."

# Verify critical pods are running
check_dependencies() {
    if ! command -v minikube &> /dev/null; then
        echo "Installing minikube..."
        brew install minikube
    fi
    
    if ! command -v kubectl &> /dev/null; then
        echo "Installing kubectl..."
        brew install kubectl
    fi
}

check_cluster() {
    check_dependencies
    
    echo "Initializing fresh Kubernetes cluster..."
    minikube delete
    minikube start --driver=docker --cpus=4 --memory=8g --wait=all --alsologtostderr -v=5 --embed-certs
    minikube addons enable ingress
    kubectl config use-context minikube
    echo "Cluster version: $(kubectl version --short)"
    
    # Deploy manifests
    echo "Applying Kubernetes manifests..."
    kubectl apply -f k8s/
}

check_pods() {
    echo "Waiting for Boulder pods to be ready..."
    local timeout=600 start_time=$(date +%s)
    
    echo "Timeout set to ${timeout} seconds"
    echo "Cluster status:"
    minikube status
    echo "Initial pod status:"
    kubectl get pods -l app=boulder --request-timeout=10s
    
    while : ; do
        local pod_status=$(kubectl get pods -l app=boulder --request-timeout=10s -o jsonpath='{range .items[*]}{.metadata.name}:{.status.phase}{":"}{.status.containerStatuses[*].ready}{"\n"}{end}' 2>/dev/null)
        local elapsed=$(( $(date +%s) - start_time ))
        
        if [[ -z "$pod_status" && $elapsed -gt 30 ]]; then
            echo "ERROR: No Boulder pods found after 30 seconds"
            exit 1
        fi

        if [[ -n "$pod_status" ]] && ! echo "$pod_status" | grep -v "Running:true" >/dev/null; then
            echo "All Boulder pods are running and ready"
            return
        fi

        if [[ $elapsed -ge $timeout ]]; then
            echo "ERROR: Timed out after ${timeout} seconds waiting for pods"
            kubectl get pods -l app=boulder --request-timeout=10s
            exit 1
        fi
        
        echo -n "."  # Progress indicator
        sleep 5
    done
}

# Verify services have endpoints
check_services() {
    kubectl get endpoints -l app=boulder --request-timeout=10s | grep -v '<none>'
}

# Verify database connectivity
check_db() {
    kubectl exec deployment/bmysql-deployment --request-timeout=10s -- mysql -usa -p$MYSQL_SA_PASSWORD -h boulder-mysql -e "SHOW DATABASES;" | grep -q boulder_sa_integration
}

# Verify Redis connectivity
check_redis() {
    kubectl exec deployment/bredis-1-deployment --request-timeout=10s -- redis-cli PING | grep -q PONG
}

# Handle Ctrl-C cleanup
trap "echo -e '\nTest interrupted by user'; exit 130" SIGINT

# Main test execution with timing
main() {
    local start_time=$(date +%s)
    
    time check_cluster
    time check_pods
    time check_services || { echo "ERROR: Boulder services missing endpoints"; exit 1; }
    time check_db || { echo "ERROR: Database connectivity test failed"; exit 1; }
    time check_redis || { echo "ERROR: Redis connectivity test failed"; exit 1; }
    
    local duration=$(( $(date +%s) - start_time ))
    echo -e "\nAll smoke tests passed successfully in ${duration} seconds!"
}

main
