# HSM Security Architecture for Boulder CA

## Overview

This document defines the Hardware Security Module (HSM) integration architecture for Boulder Certificate Authority operations in Kubernetes. The architecture ensures that private keys for CA operations are never exposed outside of secure HSM storage.

## Security Requirements

### Critical Security Principles

1. **Private Key Isolation**: CA private keys MUST never exist as files or in Kubernetes secrets
2. **HSM-Only Storage**: All signing keys generated and stored exclusively in HSM
3. **Public-Only Kubernetes**: Only public certificates and PKCS#11 configurations in K8s secrets
4. **Ceremony Tool Usage**: Boulder's official `ceremony` tool used for all key generation
5. **Audit Trail**: All HSM operations logged for security audit compliance

## Architecture Design

### Phase 1: Local SoftHSM (Current Implementation)

**Phase 1 Approach:** Uses local SoftHSM installation matching Boulder's test environment approach. This replicates the `docker-compose up` development environment functionality.

```
┌─────────────────────────────────────────┐
│      Host System (macOS/Linux)          │
│  ┌─────────────────────────────────────┐ │
│  │     Local SoftHSM2 Installation     │ │
│  │  - /usr/local/lib/softhsm/          │ │
│  │  - ~/.softhsm2/softhsm2.conf        │ │
│  │  - Token storage directory          │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
              │ Local PKCS#11 API
┌─────────────▼─────────────────────────────┐
│         Boulder CA Pod                    │
│  ┌─────────────────────────────────────┐  │
│  │     Boulder CA Service              │  │
│  │  - Reads PKCS#11 config files      │  │
│  │  - References local HSM slots      │  │
│  │  - Uses Boulder ceremony tool      │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘

Kubernetes Secret: webpki-certs
├── root-rsa.cert.pem          (Public certificate)
├── root-ecdsa.cert.pem        (Public certificate)
├── int-rsa-a.cert.pem         (Public certificate)
├── int-rsa-a.pkcs11.json      (Local HSM slot reference)
├── int-ecdsa-a.cert.pem       (Public certificate)
├── int-ecdsa-a.pkcs11.json    (Local HSM slot reference)
└── ... (additional intermediates)

Local SoftHSM Token Storage:
├── vendor/github.com/letsencrypt/boulder/test/certs/
│   └── .softhsm-tokens/
│       ├── token_slot_X       (Root RSA private key)
│       ├── token_slot_Y       (Root ECDSA private key)
│       ├── token_slot_Z       (Int RSA A private key)
│       └── token_slot_W       (Int ECDSA A private key)
```

### Phase 2: Containerized Network HSM (Future)

**Phase 2 Approach:** Containerized SoftHSM with pkcs11-proxy for network-based access, preparing for production HSM integration.

```
┌─────────────────────────────────────────┐
│         Boulder CA Pod                   │
│  ┌────────────────────────────────────┐ │
│  │     Boulder CA Service              │ │
│  │  - Uses libpkcs11-proxy.so          │ │
│  │  - Connects via network to HSM      │ │
│  └──────────┬─────────────────────────┘ │
│             │ PKCS#11 Network Protocol   │
└─────────────┼─────────────────────────────┘
              │ TLS/mTLS
┌─────────────▼─────────────────────────────┐
│        HSM Proxy Container                │
│  ┌─────────────────────────────────────┐  │
│  │      pkcs11-proxy + SoftHSM2        │  │
│  │  - Network PKCS#11 interface        │  │
│  │  - TLS encryption                   │  │
│  │  - Token storage in PV              │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘
```

### Production Environment (Network HSM)

```
┌─────────────────────────────────────────┐
│         Boulder CA Pod                   │
│  ┌────────────────────────────────────┐ │
│  │     Boulder CA Service              │ │
│  │  - Reads PKCS#11 config files      │ │
│  │  - Connects via PKCS#11 network    │ │
│  └──────────┬─────────────────────────┘ │
│             │ PKCS#11 Network Protocol   │
└─────────────┼─────────────────────────────┘
              │ TLS/mTLS
┌─────────────▼─────────────────────────────┐
│     Production HSM Cluster                │
│  ┌─────────────────────────────────────┐  │
│  │    Hardware Security Module         │  │
│  │  - FIPS 140-2 Level 3 certified    │  │
│  │  - Keys generated in hardware       │  │
│  │  - Keys never exportable            │  │
│  │  - High availability cluster        │  │
│  │  - Geographic distribution          │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘

HSM Access Controls:
├── Network HSM authentication (mTLS)
├── Slot-level access controls
├── PIN-based authentication
└── Audit logging (FIPS compliance)
```

## Certificate Hierarchy

### WebPKI Structure

```
Root CA (RSA 4096-bit)
├── Intermediate CA (RSA-A, 2048-bit)
├── Intermediate CA (RSA-B, 2048-bit)  
└── Intermediate CA (RSA-C, 2048-bit)

Root CA (ECDSA P-256)
├── Intermediate CA (ECDSA-A, P-256)
├── Intermediate CA (ECDSA-B, P-256)
└── Intermediate CA (ECDSA-C, P-256)
```

### Key Storage Mapping

| Certificate | Private Key Location | Public Cert Location | PKCS#11 Config |
|-------------|---------------------|----------------------|----------------|
| `root-rsa` | SoftHSM Slot (varies) | `webpki-certs` secret | N/A |
| `root-ecdsa` | SoftHSM Slot (varies) | `webpki-certs` secret | N/A |
| `int-rsa-a` | SoftHSM Slot (varies) | `webpki-certs` secret | `webpki-certs` secret |
| `int-rsa-b` | SoftHSM Slot (varies) | `webpki-certs` secret | `webpki-certs` secret |
| `int-rsa-c` | SoftHSM Slot (varies) | `webpki-certs` secret | `webpki-certs` secret |
| `int-ecdsa-a` | SoftHSM Slot (varies) | `webpki-certs` secret | `webpki-certs` secret |
| `int-ecdsa-b` | SoftHSM Slot (varies) | `webpki-certs` secret | `webpki-certs` secret |
| `int-ecdsa-c` | SoftHSM Slot (varies) | `webpki-certs` secret | `webpki-certs` secret |

## Implementation Details

### Boulder Ceremony Tool Integration

The secure certificate generation follows Boulder's official approach:

1. **Tool Chain**: [`generate.sh`](../vendor/github.com/letsencrypt/boulder/test/certs/generate.sh) → [`webpki.go`](../vendor/github.com/letsencrypt/boulder/test/certs/webpki.go) → `ceremony` tool
2. **HSM Integration**: Uses PKCS#11 for all cryptographic operations  
3. **Key Generation**: Keys generated directly in HSM (never on filesystem)
4. **Slot Management**: Dynamic slot allocation with parsed slot IDs

### PKCS#11 Configuration Format

Example PKCS#11 configuration for intermediate certificate:

```json
{
  "module": "/usr/local/lib/softhsm/libsofthsm2.so",
  "tokenLabel": "int rsa a", 
  "pin": "1234",
  "privateKeyLabel": "int rsa a"
}
```

### Boulder CA Service Integration

The CA service references certificates via PKCS#11 configuration:

```json
{
  "ca": {
    "issuance": {
      "issuers": [
        {
          "active": true,
          "location": {
            "configFile": "/etc/boulder/webpki/int-ecdsa-a.pkcs11.json",
            "certFile": "/etc/boulder/webpki/int-ecdsa-a.cert.pem",
            "numSessions": 2
          }
        }
      ]
    }
  }
}
```

## Security Controls

### Access Controls

1. **HSM PIN Management**:
   - Development: Hardcoded PIN "1234" (SoftHSM)
   - Production: PIN stored in Kubernetes secret with restricted access
   
2. **Network Security**:
   - Development: Local SoftHSM (no network exposure)
   - Production: mTLS-secured HSM network connections

3. **Container Security**:
   - Non-root container execution (UID 1000)
   - Read-only root filesystem
   - Dropped capabilities (ALL)
   - Security contexts enforced

### Data Protection

1. **Private Key Protection**:
   - Keys generated in HSM hardware
   - Keys never exported or backed up to filesystem
   - HSM provides tamper-resistant storage

2. **Certificate Distribution**:
   - Public certificates distributed via Kubernetes secrets
   - PKCS#11 configs reference HSM slots (no sensitive data)
   - Certificate chains built from public components only

3. **Audit Requirements**:
   - All HSM operations logged
   - Certificate generation audit trail
   - PKCS#11 session logging

## Phase Implementation Strategy

### Phase 1: PKCS#11 Proxy + SoftHSM Sidecar (Current - SPECp1.md)

**Objective**: Development and integration testing environment with sidecar HSM pattern.

- **HSM**: Containerized SoftHSM2 with pkcs11-proxy in sidecar pattern
- **Storage**: Kubernetes PersistentVolume for token storage
- **Network**: localhost:2345 PKCS#11 proxy communication
- **Security**: Sidecar isolation, PKCS#11 configuration via secrets
- **PIN Management**: Hardcoded PIN "1234" (development environment)
- **Integration**: Uses Boulder's `webpki.go` and `cmd/ceremony` tools

### Phase 2: Containerized Network HSM (Future - SPECp2.md)

**Objective**: Production-hardening with containerized HSM and network isolation.

- **HSM**: Containerized SoftHSM2 with pkcs11-proxy
- **Network**: TLS-secured PKCS#11 over network
- **Security**: Network isolation, encrypted HSM communication
- **PIN Management**: Kubernetes secrets with RBAC
- **High Availability**: Multi-proxy containers for redundancy

### Production Environment (Future)

**Objective**: Enterprise production deployment with hardware HSM.

- **HSM**: Network-attached Hardware HSM (CloudHSM, Thales, etc.)
- **Certification**: FIPS 140-2 Level 3 or higher
- **Network**: TLS/mTLS-secured HSM connectivity
- **High Availability**: Multi-HSM cluster with geographic distribution
- **PIN Management**: Enterprise secret management integration

## Implementation Roadmap

### Phase 1: Local SoftHSM (Current - SPECp1.md)
1. Use host-local SoftHSM2 installation (matches Boulder test environment)
2. Generate certificates using Boulder's ceremony tool chain
3. Store certificates in Kubernetes secrets (public only)
4. Configure Boulder CA with local PKCS#11 references
5. Validate integration test suite passes

### Phase 2: Containerized HSM (Future - SPECp2.md)
1. Deploy containerized SoftHSM with pkcs11-proxy
2. Update PKCS#11 configs for network HSM access
3. Implement TLS-secured HSM communication
4. Add HSM high availability and redundancy
5. Prepare for production HSM integration

### Production Migration (Future)
1. Deploy network-attached hardware HSM
2. Migrate keys from SoftHSM to production HSM
3. Implement enterprise-grade security controls
4. Add FIPS 140-2 Level 3 compliance validation

## Operational Procedures

### Certificate Generation Workflow

1. **Preparation**:
   ```bash
   # Ensure Boulder submodule is updated
   git submodule update --init --recursive
   
   # Install dependencies
   brew install softhsm go kubectl
   ```

2. **Certificate Generation**:
   ```bash
   # Generate certificates using Boulder ceremony tool
   ./k8s/scripts/generate-webpki-certs.sh
   ```

3. **Validation**:
   ```bash
   # Verify certificates created successfully
   kubectl get secret webpki-certs -n boulder -o yaml
   
   # Check certificate chain validity  
   kubectl exec -n boulder boulder-ca-0 -- openssl verify \
     -CAfile /etc/boulder/webpki/root-rsa.cert.pem \
     /etc/boulder/webpki/int-rsa-a.cert.pem
   ```

### Key Rotation Procedures

1. **Generate New Keys**: Use ceremony tool with new HSM slots
2. **Update PKCS#11 Configs**: Reference new slot IDs  
3. **Deploy Updated Secret**: Update `webpki-certs` with new certificates
4. **Rolling Update**: Boulder CA pods pick up new certificates
5. **Validate Operation**: Test certificate issuance with new keys

## Security Auditing

### Required Audit Events

1. **HSM Operations**:
   - Key generation events
   - Signing operations  
   - PIN authentication attempts
   - HSM session establishment/termination

2. **Certificate Operations**:
   - Certificate generation
   - Certificate chain validation
   - PKCS#11 configuration updates

3. **Kubernetes Operations**:
   - Secret creation/updates
   - Pod access to HSM resources
   - Container security policy enforcement

### Compliance Requirements

- **FIPS 140-2**: Hardware HSM certification for production
- **Common Criteria**: HSM evaluation for government deployments  
- **WebTrust**: CA security requirements compliance
- **SOC 2**: Operational security controls audit

## Troubleshooting

### Common Issues

1. **Missing HSM Module**:
   ```
   Error: PKCS#11 module not found
   Solution: Install SoftHSM2 or verify HSM module path
   ```

2. **HSM Slot Not Found**:
   ```
   Error: PKCS#11 token not found
   Solution: Regenerate certificates, slot IDs may have changed
   ```

3. **PIN Authentication Failure**:
   ```
   Error: PKCS#11 PIN incorrect  
   Solution: Verify PIN in PKCS#11 config matches HSM token PIN
   ```

## References

- [Boulder Certificate Generation](../vendor/github.com/letsencrypt/boulder/test/certs/README.md)
- [Boulder Ceremony Tool](../vendor/github.com/letsencrypt/boulder/test/certs/webpki.go)
- [Boulder Reference Guide](../reference/BOULDER.md)
- [PKCS#11 Standard](http://docs.oasis-open.org/pkcs11/pkcs11-base/v2.40/)
- [FIPS 140-2 Requirements](https://csrc.nist.gov/publications/detail/fips/140/2/final)
