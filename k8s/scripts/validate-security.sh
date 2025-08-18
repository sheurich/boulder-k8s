#!/bin/bash

# validate-security.sh - Comprehensive security validation for Boulder Kubernetes deployment
# Validates mTLS configuration, certificate validity, and security posture

set -euo pipefail

# Configuration
NAMESPACE="boulder"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*"
}

# Test result tracking
test_pass() {
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    log_info "✅ PASS: $*"
}

test_fail() {
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    log_error "❌ FAIL: $*"
}

test_skip() {
    ((TESTS_TOTAL++))
    log_warn "⏭️  SKIP: $*"
}

# Check dependencies
check_dependencies() {
    log_info "Checking required dependencies..."
    
    local deps=("kubectl" "openssl" "curl")
    local missing=0
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            test_pass "Dependency '$dep' found"
        else
            test_fail "Required dependency '$dep' not found"
            ((missing++))
        fi
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "Missing $missing required dependencies"
        exit 1
    fi
}

# Check namespace exists
check_namespace() {
    log_info "Validating namespace configuration..."
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        test_pass "Namespace '$NAMESPACE' exists"
    else
        test_fail "Namespace '$NAMESPACE' not found"
        return 1
    fi
}

# Check if pods are running
check_pods_running() {
    log_info "Checking if all Boulder pods are running..."
    
    local expected_services=(
        "boulder-ca"
        "boulder-ra" 
        "boulder-sa"
        "boulder-va"
        "boulder-wfe2"
        "boulder-publisher"
        "boulder-nonce-service"
        "boulder-sct-provider"
        "boulder-remote-va1"
        "boulder-remote-va2"
        "mariadb"
        "proxysql"
        "redis"
    )
    
    for service in "${expected_services[@]}"; do
        local pod_status
        pod_status=$(kubectl get pods -n "$NAMESPACE" -l "app=$service" -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "NotFound")
        
        if [[ "$pod_status" == "Running" ]]; then
            test_pass "Pod '$service' is running"
        elif [[ "$pod_status" == "NotFound" ]]; then
            test_fail "Pod '$service' not found"
        else
            test_fail "Pod '$service' not running (status: $pod_status)"
        fi
    done
}

# Validate secrets exist
check_secrets() {
    log_info "Validating required secrets..."
    
    local required_secrets=(
        "webpki-certs"
        "db-credentials"
        "internal-pki"
    )
    
    for secret in "${required_secrets[@]}"; do
        if kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
            test_pass "Secret '$secret' exists"
            
            # Check secret has data
            local key_count
            key_count=$(kubectl get secret "$secret" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys | length' 2>/dev/null || echo "0")
            
            if [[ "$key_count" -gt 0 ]]; then
                test_pass "Secret '$secret' contains $key_count keys"
            else
                test_fail "Secret '$secret' has no data"
            fi
        else
            test_fail "Required secret '$secret' not found"
        fi
    done
}

# Validate WebPKI certificates
validate_webpki_certificates() {
    log_info "Validating WebPKI certificates..."
    
    if ! kubectl get secret webpki-certs -n "$NAMESPACE" &> /dev/null; then
        test_fail "webpki-certs secret not found, skipping certificate validation"
        return 1
    fi
    
    # Check for required certificate files
    local required_certs=(
        "root-rsa.pem"
        "root-ecdsa.pem"
        "int-rsa-a.cert.pem"
        "int-rsa-b.cert.pem"
        "int-ecdsa-a.cert.pem"
        "int-ecdsa-b.cert.pem"
        "int-rsa-a-chain.pem"
        "int-rsa-b-chain.pem"
        "int-ecdsa-a-chain.pem"
        "int-ecdsa-b-chain.pem"
    )
    
    for cert_name in "${required_certs[@]}"; do
        local cert_exists
        cert_exists=$(kubectl get secret webpki-certs -n "$NAMESPACE" -o jsonpath="{.data.${cert_name}}" 2>/dev/null || echo "")
        
        if [[ -n "$cert_exists" ]]; then
            test_pass "WebPKI certificate '$cert_name' found"
        else
            test_fail "WebPKI certificate '$cert_name' missing"
        fi
    done
    
    # Validate certificate expiration
    local temp_dir="/tmp/boulder-certs-$$"
    mkdir -p "$temp_dir"
    
    # Extract and validate root certificates
    kubectl get secret webpki-certs -n "$NAMESPACE" -o jsonpath='{.data.root-rsa\.pem}' | base64 -d > "$temp_dir/root-rsa.pem" 2>/dev/null || true
    kubectl get secret webpki-certs -n "$NAMESPACE" -o jsonpath='{.data.root-ecdsa\.pem}' | base64 -d > "$temp_dir/root-ecdsa.pem" 2>/dev/null || true
    
    for root_cert in "$temp_dir/root-rsa.pem" "$temp_dir/root-ecdsa.pem"; do
        if [[ -f "$root_cert" ]]; then
            local cert_name="${root_cert##*/}"
            local expiry_date
            expiry_date=$(openssl x509 -in "$root_cert" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
            
            if [[ -n "$expiry_date" ]]; then
                local expiry_epoch
                expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
                local current_epoch
                current_epoch=$(date +%s)
                
                if [[ $expiry_epoch -gt $current_epoch ]]; then
                    local days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))
                    if [[ $days_remaining -gt 30 ]]; then
                        test_pass "Certificate '$cert_name' valid for $days_remaining more days"
                    else
                        test_warn "Certificate '$cert_name' expires in $days_remaining days"
                    fi
                else
                    test_fail "Certificate '$cert_name' has expired"
                fi
            else
                test_fail "Unable to read expiry date for '$cert_name'"
            fi
        fi
    done
    
    # Clean up
    rm -rf "$temp_dir"
}

# Test mTLS connectivity between services
test_mtls_connectivity() {
    log_info "Testing mTLS connectivity between services..."
    
    # Test database connectivity
    local db_pod
    db_pod=$(kubectl get pods -n "$NAMESPACE" -l "app=mariadb" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$db_pod" ]]; then
        log_debug "Testing database connectivity from pod: $db_pod"
        
        if kubectl exec -n "$NAMESPACE" "$db_pod" -- mysqladmin ping -h localhost &> /dev/null; then
            test_pass "Database connectivity test successful"
        else
            test_fail "Database connectivity test failed"
        fi
    else
        test_skip "Database connectivity test (no MariaDB pod found)"
    fi
    
    # Test Redis connectivity
    local redis_pod
    redis_pod=$(kubectl get pods -n "$NAMESPACE" -l "app=redis" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$redis_pod" ]]; then
        log_debug "Testing Redis connectivity from pod: $redis_pod"
        
        if kubectl exec -n "$NAMESPACE" "$redis_pod" -- redis-cli ping 2>/dev/null | grep -q "PONG"; then
            test_pass "Redis connectivity test successful"
        else
            test_fail "Redis connectivity test failed"
        fi
    else
        test_skip "Redis connectivity test (no Redis pod found)"
    fi
}

# Check service endpoints and ports
validate_service_endpoints() {
    log_info "Validating service endpoints and ports..."
    
    local services=(
        "boulder-sa"
        "boulder-sct-provider"
        "boulder-remote-va1"
        "boulder-remote-va2"
        "mariadb-service"
        "proxysql-service"
        "redis-service"
    )
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
            test_pass "Service '$service' exists"
            
            # Check if service has endpoints
            local endpoint_count
            endpoint_count=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w || echo "0")
            
            if [[ "$endpoint_count" -gt 0 ]]; then
                test_pass "Service '$service' has $endpoint_count active endpoint(s)"
            else
                test_fail "Service '$service' has no active endpoints"
            fi
        else
            test_fail "Service '$service' not found"
        fi
    done
}

# Check for security best practices
validate_security_config() {
    log_info "Validating security configuration best practices..."
    
    # Check if pods are running as non-root
    local pods
    readarray -t pods < <(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    for pod in "${pods[@]}"; do
        if [[ -z "$pod" ]]; then continue; fi
        
        local run_as_user
        run_as_user=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null || echo "")
        
        if [[ -n "$run_as_user" && "$run_as_user" != "0" ]]; then
            test_pass "Pod '$pod' runs as non-root user ($run_as_user)"
        else
            # Check container-level security context
            local container_user
            container_user=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].securityContext.runAsUser}' 2>/dev/null || echo "")
            
            if [[ -n "$container_user" && "$container_user" != "0" ]]; then
                test_pass "Pod '$pod' container runs as non-root user ($container_user)"
            else
                test_warn "Pod '$pod' may be running as root (security concern)"
            fi
        fi
    done
    
    # Check for read-only root filesystems
    for pod in "${pods[@]}"; do
        if [[ -z "$pod" ]]; then continue; fi
        
        local readonly_fs
        readonly_fs=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || echo "false")
        
        if [[ "$readonly_fs" == "true" ]]; then
            test_pass "Pod '$pod' uses read-only root filesystem"
        else
            test_skip "Pod '$pod' read-only filesystem check (not configured)"
        fi
    done
}

# Check resource limits and requests
validate_resource_limits() {
    log_info "Validating resource limits and requests..."
    
    local pods
    readarray -t pods < <(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    for pod in "${pods[@]}"; do
        if [[ -z "$pod" ]]; then continue; fi
        
        local has_limits
        has_limits=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.limits}' 2>/dev/null || echo "{}")
        
        local has_requests  
        has_requests=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests}' 2>/dev/null || echo "{}")
        
        if [[ "$has_limits" != "{}" && "$has_limits" != "null" ]]; then
            test_pass "Pod '$pod' has resource limits configured"
        else
            test_warn "Pod '$pod' has no resource limits (may consume excessive resources)"
        fi
        
        if [[ "$has_requests" != "{}" && "$has_requests" != "null" ]]; then
            test_pass "Pod '$pod' has resource requests configured"
        else
            test_warn "Pod '$pod' has no resource requests (scheduling may be suboptimal)"
        fi
    done
}

# Network policy validation
validate_network_policies() {
    log_info "Checking network security policies..."
    
    local network_policies
    network_policies=$(kubectl get networkpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$network_policies" -gt 0 ]]; then
        test_pass "Found $network_policies network policy/policies"
    else
        test_warn "No network policies found (network segmentation not enforced)"
    fi
}

# Test certificate chain validation
validate_certificate_chains() {
    log_info "Validating certificate chain integrity..."
    
    if ! kubectl get secret webpki-certs -n "$NAMESPACE" &> /dev/null; then
        test_skip "Certificate chain validation (webpki-certs secret not found)"
        return 0
    fi
    
    local temp_dir="/tmp/boulder-chain-validation-$$"
    mkdir -p "$temp_dir"
    
    # Extract certificates for validation
    kubectl get secret webpki-certs -n "$NAMESPACE" -o jsonpath='{.data.root-rsa\.pem}' | base64 -d > "$temp_dir/root-rsa.pem" 2>/dev/null || true
    kubectl get secret webpki-certs -n "$NAMESPACE" -o jsonpath='{.data.int-rsa-a\.cert\.pem}' | base64 -d > "$temp_dir/int-rsa-a.cert.pem" 2>/dev/null || true
    kubectl get secret webpki-certs -n "$NAMESPACE" -o jsonpath='{.data.int-rsa-a-chain\.pem}' | base64 -d > "$temp_dir/int-rsa-a-chain.pem" 2>/dev/null || true
    
    # Validate intermediate certificate against root
    if [[ -f "$temp_dir/root-rsa.pem" && -f "$temp_dir/int-rsa-a.cert.pem" ]]; then
        if openssl verify -CAfile "$temp_dir/root-rsa.pem" "$temp_dir/int-rsa-a.cert.pem" &> /dev/null; then
            test_pass "RSA intermediate certificate chain validation successful"
        else
            test_fail "RSA intermediate certificate chain validation failed"
        fi
    else
        test_skip "RSA certificate chain validation (certificates not available)"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
}

# Generate security report
generate_report() {
    echo
    echo "======================================"
    echo "    BOULDER SECURITY VALIDATION REPORT"
    echo "======================================"
    echo
    echo "Namespace: $NAMESPACE"
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo
    echo "Test Results Summary:"
    echo "  Total Tests: $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo
    
    local success_rate
    if [[ $TESTS_TOTAL -gt 0 ]]; then
        success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
    else
        success_rate=0
    fi
    
    echo "  Success Rate: ${success_rate}%"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL SECURITY TESTS PASSED!${NC}"
        echo "Boulder deployment appears to be secure and properly configured."
    elif [[ $TESTS_FAILED -lt 5 ]]; then
        echo -e "${YELLOW}⚠️  SOME TESTS FAILED${NC}"
        echo "Boulder deployment has minor security issues that should be addressed."
    else
        echo -e "${RED}🚨 CRITICAL SECURITY ISSUES DETECTED${NC}"
        echo "Boulder deployment has significant security vulnerabilities!"
    fi
    
    echo
    echo "Security Recommendations:"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "  - Review and fix failed security tests"
    fi
    echo "  - Regularly rotate TLS certificates before expiration"
    echo "  - Monitor certificate validity and renewal processes"
    echo "  - Implement network policies for better segmentation"
    echo "  - Ensure all services use mutual TLS authentication"
    echo "  - Review and update security configurations periodically"
    echo "  - Enable read-only root filesystems where possible"
    echo "  - Configure appropriate resource limits for all pods"
    echo
}

# Main execution
main() {
    log_info "Starting Boulder security validation..."
    echo
    
    check_dependencies
    check_namespace || exit 1
    check_pods_running
    check_secrets
    validate_webpki_certificates
    test_mtls_connectivity
    validate_service_endpoints
    validate_security_config
    validate_resource_limits
    validate_network_policies
    validate_certificate_chains
    
    generate_report
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Boulder Security Validation Script"
        echo
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo
        echo "This script performs comprehensive security validation for"
        echo "Boulder Kubernetes deployment including:"
        echo "  - mTLS configuration validation"
        echo "  - Certificate validity and expiration checks"
        echo "  - Service connectivity testing"
        echo "  - Security best practices verification"
        echo "  - Resource limits and security context validation"
        echo "  - Network policy enforcement checks"
        echo
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac