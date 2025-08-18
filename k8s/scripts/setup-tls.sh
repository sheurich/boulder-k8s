#!/bin/bash

# Boulder Kubernetes TLS Setup Script
# Deploys cert-manager and configures TLS certificates for all Boulder services
set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")"
CERT_MANAGER_VERSION="v1.15.0"
TIMEOUT=${TIMEOUT:-600}  # 10 minutes default timeout

# Color output functions
red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
blue() { echo -e "\033[34m$*\033[0m"; }

# Logging functions
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"; }
error() { echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2; }
warn() { echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*" >&2; }

# Help function
show_help() {
    cat << EOF
Boulder Kubernetes TLS Setup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -t, --timeout SEC   Timeout for waiting operations (default: 600)
    -v, --verbose       Enable verbose output
    --dry-run           Show what would be done without executing
    --skip-crds         Skip CRD installation (use if already installed)
    --cleanup           Remove all TLS resources and cert-manager

EXAMPLES:
    $0                          # Deploy cert-manager with TLS certificates
    $0 --verbose                # Deploy with verbose output
    $0 --timeout 300            # Deploy with 5-minute timeout
    $0 --cleanup                # Remove all TLS infrastructure

EOF
}

# Parse command line arguments
VERBOSE=false
DRY_RUN=false
SKIP_CRDS=false
CLEANUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-crds)
            SKIP_CRDS=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose mode if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Utility functions
kubectl_apply() {
    local file="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would apply $file"
        kubectl apply --dry-run=client -f "$file"
    else
        log "Applying $file"
        kubectl apply -f "$file"
    fi
}

kubectl_delete() {
    local file="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would delete $file"
    else
        log "Deleting $file"
        kubectl delete -f "$file" --ignore-not-found=true
    fi
}

wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-$TIMEOUT}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would wait for deployment $deployment in namespace $namespace"
        return 0
    fi
    
    log "Waiting for deployment $deployment in namespace $namespace (timeout: ${timeout}s)"
    if ! kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="${timeout}s"; then
        error "Deployment $deployment failed to become ready within ${timeout}s"
        return 1
    fi
    green "✓ Deployment $deployment is ready"
}

wait_for_certificate() {
    local namespace="$1"
    local cert_name="$2"
    local timeout="${3:-$TIMEOUT}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would wait for certificate $cert_name in namespace $namespace"
        return 0
    fi
    
    log "Waiting for certificate $cert_name in namespace $namespace (timeout: ${timeout}s)"
    local end_time=$((SECONDS + timeout))
    
    while [[ $SECONDS -lt $end_time ]]; do
        if kubectl get certificate "$cert_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            green "✓ Certificate $cert_name is ready"
            return 0
        fi
        sleep 5
    done
    
    error "Certificate $cert_name failed to become ready within ${timeout}s"
    kubectl describe certificate "$cert_name" -n "$namespace" || true
    return 1
}

wait_for_clusterissuer() {
    local issuer_name="$1"
    local timeout="${2:-$TIMEOUT}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would wait for ClusterIssuer $issuer_name"
        return 0
    fi
    
    log "Waiting for ClusterIssuer $issuer_name (timeout: ${timeout}s)"
    local end_time=$((SECONDS + timeout))
    
    while [[ $SECONDS -lt $end_time ]]; do
        if kubectl get clusterissuer "$issuer_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            green "✓ ClusterIssuer $issuer_name is ready"
            return 0
        fi
        sleep 5
    done
    
    error "ClusterIssuer $issuer_name failed to become ready within ${timeout}s"
    kubectl describe clusterissuer "$issuer_name" || true
    return 1
}

# Cleanup function
cleanup_tls() {
    log "Starting TLS cleanup..."
    
    # Delete certificates
    kubectl_delete "$K8S_DIR/certificates/dns-certs.yaml"
    kubectl_delete "$K8S_DIR/certificates/infrastructure-certs.yaml"
    kubectl_delete "$K8S_DIR/certificates/grpc-server-certs.yaml"
    
    # Delete CA issuers and Let's Encrypt ClusterIssuers
    kubectl_delete "$K8S_DIR/cert-manager/boulder-ca-issuer.yaml"
    kubectl_delete "$K8S_DIR/cert-manager/letsencrypt-clusterissuer.yaml"
    
    # Delete cert-manager
    kubectl_delete "$K8S_DIR/cert-manager/cert-manager.yaml"
    
    log "TLS cleanup completed"
}

# Pre-deployment checks
pre_deployment_checks() {
    log "Running pre-deployment checks..."
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check required directories
    for dir in "$K8S_DIR/cert-manager" "$K8S_DIR/certificates"; do
        if [[ ! -d "$dir" ]]; then
            error "Required directory not found: $dir"
            exit 1
        fi
    done
    
    # Check required files
    local required_files=(
        "$K8S_DIR/cert-manager/cert-manager.yaml"
        "$K8S_DIR/cert-manager/boulder-ca-issuer.yaml"
        "$K8S_DIR/cert-manager/letsencrypt-clusterissuer.yaml"
        "$K8S_DIR/certificates/grpc-server-certs.yaml"
        "$K8S_DIR/certificates/infrastructure-certs.yaml"
        "$K8S_DIR/certificates/dns-certs.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error "Required file not found: $file"
            exit 1
        fi
    done
    
    green "✓ Pre-deployment checks passed"
}

# Deploy cert-manager
deploy_cert_manager() {
    log "Deploying cert-manager..."
    
    # Apply cert-manager CRDs first if not skipping
    if [[ "$SKIP_CRDS" == "false" ]]; then
        log "Installing cert-manager CRDs..."
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.crds.yaml"
        else
            log "DRY-RUN: Would install cert-manager CRDs from GitHub"
        fi
    fi
    
    # Apply cert-manager deployment
    kubectl_apply "$K8S_DIR/cert-manager/cert-manager.yaml"
    
    # Wait for cert-manager deployments to be ready
    wait_for_deployment "cert-manager" "cert-manager"
    wait_for_deployment "cert-manager" "cert-manager-cainjector"
    wait_for_deployment "cert-manager" "cert-manager-webhook"
    
    green "✓ cert-manager deployed successfully"
}

# Setup CA hierarchy
setup_ca_hierarchy() {
    log "Setting up Boulder CA hierarchy..."
    
    # Ensure boulder namespace exists
    if [[ "$DRY_RUN" == "false" ]]; then
        kubectl create namespace boulder --dry-run=client -o yaml | kubectl apply -f -
    else
        log "DRY-RUN: Would create boulder namespace"
    fi
    
    # Apply CA issuers
    kubectl_apply "$K8S_DIR/cert-manager/boulder-ca-issuer.yaml"
    
    # Wait for root CA certificate to be ready
    wait_for_certificate "boulder" "root-ca-cert"
    wait_for_certificate "boulder" "intermediate-ca-cert"
    
    green "✓ Boulder CA hierarchy established"
}

# Deploy Let's Encrypt ClusterIssuers
deploy_letsencrypt_issuers() {
    log "Deploying Let's Encrypt ClusterIssuers..."
    
    # Apply Let's Encrypt ClusterIssuers
    kubectl_apply "$K8S_DIR/cert-manager/letsencrypt-clusterissuer.yaml"
    
    # Wait for ClusterIssuers to be ready
    wait_for_clusterissuer "letsencrypt-staging"
    wait_for_clusterissuer "letsencrypt-production"
    
    green "✓ Let's Encrypt ClusterIssuers deployed successfully"
}

# Deploy service certificates
deploy_service_certificates() {
    log "Deploying service certificates..."
    
    # Apply certificate resources
    kubectl_apply "$K8S_DIR/certificates/grpc-server-certs.yaml"
    kubectl_apply "$K8S_DIR/certificates/infrastructure-certs.yaml"
    kubectl_apply "$K8S_DIR/certificates/dns-certs.yaml"
    
    # Wait for key certificates to be ready
    local key_certificates=(
        "boulder-wfe2-grpc-cert"
        "boulder-ra-grpc-cert"
        "boulder-ca-grpc-cert"
        "boulder-sa-grpc-cert"
        "boulder-va-grpc-cert"
        "mariadb-server-cert"
        "redis-server-cert"
    )
    
    for cert in "${key_certificates[@]}"; do
        wait_for_certificate "boulder" "$cert"
    done
    
    green "✓ Service certificates deployed successfully"
}

# Verify TLS setup
verify_tls_setup() {
    log "Verifying TLS setup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would verify TLS setup"
        return 0
    fi
    
    # Check cert-manager is healthy
    if ! kubectl get pods -n cert-manager -l app.kubernetes.io/name=cert-manager --field-selector=status.phase=Running | grep -q cert-manager; then
        error "cert-manager pods are not running"
        return 1
    fi
    
    # Check CA hierarchy
    if ! kubectl get secret root-ca-secret -n boulder &>/dev/null; then
        error "Root CA secret not found"
        return 1
    fi
    
    if ! kubectl get secret intermediate-ca-secret -n boulder &>/dev/null; then
        error "Intermediate CA secret not found"
        return 1
    fi
    
    # Check Let's Encrypt ClusterIssuers
    local clusterissuers=(
        "letsencrypt-staging"
        "letsencrypt-production"
    )
    
    for issuer in "${clusterissuers[@]}"; do
        if ! kubectl get clusterissuer "$issuer" &>/dev/null; then
            error "ClusterIssuer not found: $issuer"
            return 1
        fi
        
        # Check if issuer is ready
        if ! kubectl get clusterissuer "$issuer" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            error "ClusterIssuer not ready: $issuer"
            return 1
        fi
    done
    
    # Check service certificates
    local cert_secrets=(
        "boulder-wfe2-grpc-tls"
        "boulder-ra-grpc-tls"
        "boulder-ca-grpc-tls"
        "boulder-sa-grpc-tls"
        "mariadb-server-tls"
        "redis-server-tls"
    )
    
    for secret in "${cert_secrets[@]}"; do
        if ! kubectl get secret "$secret" -n boulder &>/dev/null; then
            error "Certificate secret not found: $secret"
            return 1
        fi
    done
    
    green "✓ TLS setup verification completed successfully"
}

# Main execution
main() {
    blue "Boulder Kubernetes TLS Setup"
    blue "=============================="
    
    if [[ "$CLEANUP" == "true" ]]; then
        cleanup_tls
        exit 0
    fi
    
    pre_deployment_checks
    deploy_cert_manager
    setup_ca_hierarchy
    deploy_letsencrypt_issuers
    deploy_service_certificates
    verify_tls_setup
    
    green ""
    green "🎉 TLS setup completed successfully!"
    green ""
    green "Certificate issuers available:"
    green "  • Internal CA: root-ca-issuer, intermediate-ca-issuer"
    green "  • Let's Encrypt: letsencrypt-staging, letsencrypt-production"
    green ""
    green "Next steps:"
    green "  1. Update Boulder service configurations to use mTLS certificates"
    green "  2. Update infrastructure services to use TLS certificates"
    green "  3. Run: ./k8s/scripts/deploy.sh to deploy Boulder services"
    green "  4. Run: ./k8s/scripts/health-check.sh to verify deployment"
    green ""
}

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Execute main function
main "$@"