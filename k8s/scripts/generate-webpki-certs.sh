#!/bin/bash

# generate-webpki-certs.sh - Generate WebPKI certificates for Boulder services
# This script creates the certificate hierarchy needed for Boulder CA operations
# Based on Boulder's test/certs/generate.sh but adapted for Kubernetes deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/../tmp/webpki-certs"
NAMESPACE="boulder"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check dependencies
check_dependencies() {
    log_info "Checking required dependencies..."
    
    local deps=("openssl" "kubectl")
    local missing=0
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required dependency '$dep' not found"
            ((missing++))
        fi
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "Missing $missing required dependencies"
        exit 1
    fi
    
    log_info "All dependencies found"
}

# Create certificate directory
create_cert_dir() {
    log_info "Creating certificate directory: $CERT_DIR"
    mkdir -p "$CERT_DIR"
    cd "$CERT_DIR"
}

# Generate CA certificates (RSA and ECDSA)
generate_ca_certificates() {
    log_info "Generating CA certificates..."
    
    # Generate RSA Root CA
    log_debug "Generating RSA Root CA..."
    openssl genrsa -out root-rsa.key 4096
    openssl req -new -x509 -sha256 -days 3650 -key root-rsa.key -out root-rsa.pem \
        -subj "/C=US/ST=California/L=San Francisco/O=Boulder Test CA/CN=Boulder Test Root CA (RSA)"
    
    # Generate ECDSA Root CA  
    log_debug "Generating ECDSA Root CA..."
    openssl ecparam -genkey -name prime256v1 -out root-ecdsa.key
    openssl req -new -x509 -sha256 -days 3650 -key root-ecdsa.key -out root-ecdsa.pem \
        -subj "/C=US/ST=California/L=San Francisco/O=Boulder Test CA/CN=Boulder Test Root CA (ECDSA)"
    
    log_info "CA certificates generated successfully"
}

# Generate intermediate certificates
generate_intermediate_certificates() {
    log_info "Generating intermediate certificates..."
    
    # RSA Intermediate A
    log_debug "Generating RSA Intermediate A..."
    openssl genrsa -out int-rsa-a.key 2048
    openssl req -new -sha256 -key int-rsa-a.key -out int-rsa-a.csr \
        -subj "/C=US/ST=California/L=San Francisco/O=Boulder Test CA/CN=Boulder Test Intermediate A (RSA)"
    
    cat > int-rsa-a.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_ca
[req_distinguished_name]
[v3_ca]
basicConstraints = CA:TRUE, pathlen:0
keyUsage = keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF
    
    openssl x509 -req -sha256 -days 1825 -in int-rsa-a.csr -CA root-rsa.pem -CAkey root-rsa.key \
        -out int-rsa-a.cert.pem -extensions v3_ca -extfile int-rsa-a.conf -CAcreateserial
    
    # RSA Intermediate B  
    log_debug "Generating RSA Intermediate B..."
    openssl genrsa -out int-rsa-b.key 2048
    openssl req -new -sha256 -key int-rsa-b.key -out int-rsa-b.csr \
        -subj "/C=US/ST=California/L=San Francisco/O=Boulder Test CA/CN=Boulder Test Intermediate B (RSA)"
    
    cat > int-rsa-b.conf << EOF
[req]
distinguished_name = req_distinguished_name  
req_extensions = v3_ca
[req_distinguished_name]
[v3_ca]
basicConstraints = CA:TRUE, pathlen:0
keyUsage = keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF
    
    openssl x509 -req -sha256 -days 1825 -in int-rsa-b.csr -CA root-rsa.pem -CAkey root-rsa.key \
        -out int-rsa-b.cert.pem -extensions v3_ca -extfile int-rsa-b.conf -CAcreateserial
    
    # ECDSA Intermediate A
    log_debug "Generating ECDSA Intermediate A..."
    openssl ecparam -genkey -name prime256v1 -out int-ecdsa-a.key
    openssl req -new -sha256 -key int-ecdsa-a.key -out int-ecdsa-a.csr \
        -subj "/C=US/ST=California/L=San Francisco/O=Boulder Test CA/CN=Boulder Test Intermediate A (ECDSA)"
    
    cat > int-ecdsa-a.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_ca
[req_distinguished_name]
[v3_ca]
basicConstraints = CA:TRUE, pathlen:0
keyUsage = keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF
    
    openssl x509 -req -sha256 -days 1825 -in int-ecdsa-a.csr -CA root-ecdsa.pem -CAkey root-ecdsa.key \
        -out int-ecdsa-a.cert.pem -extensions v3_ca -extfile int-ecdsa-a.conf -CAcreateserial
    
    # ECDSA Intermediate B
    log_debug "Generating ECDSA Intermediate B..."  
    openssl ecparam -genkey -name prime256v1 -out int-ecdsa-b.key
    openssl req -new -sha256 -key int-ecdsa-b.key -out int-ecdsa-b.csr \
        -subj "/C=US/ST=California/L=San Francisco/O=Boulder Test CA/CN=Boulder Test Intermediate B (ECDSA)"
    
    cat > int-ecdsa-b.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_ca
[req_distinguished_name] 
[v3_ca]
basicConstraints = CA:TRUE, pathlen:0
keyUsage = keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF
    
    openssl x509 -req -sha256 -days 1825 -in int-ecdsa-b.csr -CA root-ecdsa.pem -CAkey root-ecdsa.key \
        -out int-ecdsa-b.cert.pem -extensions v3_ca -extfile int-ecdsa-b.conf -CAcreateserial
    
    log_info "Intermediate certificates generated successfully"
}

# Generate PKCS#11 configuration files
generate_pkcs11_configs() {
    log_info "Generating PKCS#11 configuration files..."
    
    # RSA Intermediate A PKCS#11 config
    cat > int-rsa-a.json << EOF
{
  "module": "/usr/lib/softhsm/libsofthsm2.so",
  "tokenLabel": "intermediate-rsa-a",
  "pin": "1234",
  "privateKeyLabel": "intermediate-rsa-a-key"
}
EOF
    
    # RSA Intermediate B PKCS#11 config  
    cat > int-rsa-b.json << EOF
{
  "module": "/usr/lib/softhsm/libsofthsm2.so", 
  "tokenLabel": "intermediate-rsa-b",
  "pin": "1234",
  "privateKeyLabel": "intermediate-rsa-b-key"
}
EOF
    
    # ECDSA Intermediate A PKCS#11 config
    cat > int-ecdsa-a.json << EOF
{
  "module": "/usr/lib/softhsm/libsofthsm2.so",
  "tokenLabel": "intermediate-ecdsa-a", 
  "pin": "1234",
  "privateKeyLabel": "intermediate-ecdsa-a-key"
}
EOF
    
    # ECDSA Intermediate B PKCS#11 config
    cat > int-ecdsa-b.json << EOF
{
  "module": "/usr/lib/softhsm/libsofthsm2.so",
  "tokenLabel": "intermediate-ecdsa-b",
  "pin": "1234", 
  "privateKeyLabel": "intermediate-ecdsa-b-key"
}
EOF
    
    log_info "PKCS#11 configuration files created"
}

# Generate certificate chains
generate_certificate_chains() {
    log_info "Generating certificate chains..."
    
    # RSA chains
    cat int-rsa-a.cert.pem root-rsa.pem > int-rsa-a-chain.pem
    cat int-rsa-b.cert.pem root-rsa.pem > int-rsa-b-chain.pem
    
    # ECDSA chains
    cat int-ecdsa-a.cert.pem root-ecdsa.pem > int-ecdsa-a-chain.pem  
    cat int-ecdsa-b.cert.pem root-ecdsa.pem > int-ecdsa-b-chain.pem
    
    log_info "Certificate chains generated"
}

# Create Kubernetes secret
create_k8s_secret() {
    log_info "Creating Kubernetes secret 'webpki-certs'..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    # Check if secret exists and delete it
    if kubectl get secret webpki-certs -n "$NAMESPACE" &> /dev/null; then
        log_warn "Secret 'webpki-certs' already exists. Deleting..."
        kubectl delete secret webpki-certs -n "$NAMESPACE"
    fi
    
    # Create the secret with all certificate files
    kubectl create secret generic webpki-certs -n "$NAMESPACE" \
        --from-file=root-rsa.pem \
        --from-file=root-rsa.key \
        --from-file=root-ecdsa.pem \
        --from-file=root-ecdsa.key \
        --from-file=int-rsa-a.cert.pem \
        --from-file=int-rsa-a.key \
        --from-file=int-rsa-a-chain.pem \
        --from-file=int-rsa-b.cert.pem \
        --from-file=int-rsa-b.key \
        --from-file=int-rsa-b-chain.pem \
        --from-file=int-ecdsa-a.cert.pem \
        --from-file=int-ecdsa-a.key \
        --from-file=int-ecdsa-a-chain.pem \
        --from-file=int-ecdsa-b.cert.pem \
        --from-file=int-ecdsa-b.key \
        --from-file=int-ecdsa-b-chain.pem \
        --from-file=int-rsa-a.json \
        --from-file=int-rsa-b.json \
        --from-file=int-ecdsa-a.json \
        --from-file=int-ecdsa-b.json
    
    log_info "Kubernetes secret 'webpki-certs' created successfully"
}

# Verify certificates
verify_certificates() {
    log_info "Verifying generated certificates..."
    
    local cert_count=0
    local verification_failed=0
    
    # Verify intermediate certificates against root CAs
    certificates=(
        "int-rsa-a.cert.pem:root-rsa.pem"
        "int-rsa-b.cert.pem:root-rsa.pem"
        "int-ecdsa-a.cert.pem:root-ecdsa.pem"
        "int-ecdsa-b.cert.pem:root-ecdsa.pem"
    )
    
    for cert_pair in "${certificates[@]}"; do
        cert="${cert_pair%:*}"
        ca="${cert_pair#*:}"
        
        if openssl verify -CAfile "$ca" "$cert" &> /dev/null; then
            log_debug "✓ Certificate $cert verified against $ca"
            ((cert_count++))
        else
            log_error "✗ Certificate verification failed for: $cert"
            ((verification_failed++))
        fi
    done
    
    if [[ $verification_failed -eq 0 ]]; then
        log_info "All $cert_count certificates verified successfully"
        return 0
    else
        log_error "$verification_failed certificate verifications failed"
        return 1
    fi
}

# Clean up temporary files (optional)
cleanup() {
    if [[ "${1:-}" == "--cleanup" ]]; then
        log_info "Cleaning up temporary certificate files..."
        rm -rf "$CERT_DIR"
        log_info "Cleanup completed"
    else
        log_info "Certificate files saved in: $CERT_DIR"
        log_info "Run with --cleanup to remove temporary files"
    fi
}

# Display certificate information
show_certificate_info() {
    log_info "Certificate Information Summary:"
    echo
    echo "Root Certificates:"
    echo "  - root-rsa.pem (RSA 4096-bit)"
    echo "  - root-ecdsa.pem (ECDSA P-256)"
    echo
    echo "Intermediate Certificates:"
    echo "  - int-rsa-a.cert.pem (RSA 2048-bit)" 
    echo "  - int-rsa-b.cert.pem (RSA 2048-bit)"
    echo "  - int-ecdsa-a.cert.pem (ECDSA P-256)"
    echo "  - int-ecdsa-b.cert.pem (ECDSA P-256)"
    echo
    echo "Certificate Chains:"
    echo "  - int-rsa-a-chain.pem"
    echo "  - int-rsa-b-chain.pem" 
    echo "  - int-ecdsa-a-chain.pem"
    echo "  - int-ecdsa-b-chain.pem"
    echo
    echo "PKCS#11 Configurations:"
    echo "  - int-rsa-a.json"
    echo "  - int-rsa-b.json"
    echo "  - int-ecdsa-a.json" 
    echo "  - int-ecdsa-b.json"
    echo
}

# Main execution
main() {
    log_info "Starting WebPKI certificate generation for Boulder..."
    
    check_dependencies
    create_cert_dir
    generate_ca_certificates
    generate_intermediate_certificates
    generate_pkcs11_configs
    generate_certificate_chains
    verify_certificates
    create_k8s_secret
    show_certificate_info
    cleanup "$@"
    
    log_info "WebPKI certificate generation completed successfully!"
    log_info "Secret 'webpki-certs' is ready for use by Boulder CA services"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Boulder WebPKI Certificate Generation Script"
        echo
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --cleanup      Remove temporary certificate files after creation"
        echo
        echo "This script generates the complete WebPKI certificate hierarchy"
        echo "required by Boulder CA services and packages them into a"
        echo "Kubernetes secret named 'webpki-certs'."
        echo
        echo "Generated certificates:"
        echo "  - RSA and ECDSA root CA certificates"
        echo "  - RSA and ECDSA intermediate CA certificates (A & B variants)"
        echo "  - Certificate chains for validation"
        echo "  - PKCS#11 configuration files"
        echo
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac