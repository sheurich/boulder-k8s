# HSM Implementation Plan - PKCS#11 Proxy + SoftHSM Sidecar (Phase 1)

**Status**: Phase 1 Development & Integration Testing  
**Decision**: Implement PKCS#11 proxy + SoftHSM sidecar approach for Phase 1  
**Base Image**: debian:12 (consistent with boulder-k8s:latest)  
**Architecture**: Sidecar pattern with localhost communication  

## Phase 1 Architecture Decision

The **PKCS#11 proxy + SoftHSM sidecar approach** is chosen for Phase 1 because:

✅ **Boulder Tool Compatibility**: Uses Boulder's `webpki.go` and `cmd/ceremony` tools  
✅ **Future-Proof**: Phase 2 transition requires only config changes (swap SoftHSM for remote HSM)  
✅ **Better Isolation**: HSM operations contained in dedicated sidecar container  
✅ **Standard Integration**: Boulder makes standard localhost PKCS#11 calls  
✅ **Development Environment**: Suitable for development and integration testing  

**Note**: This is a development and integration test system, not production-ready. Phase 2 will add production hardening.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster - Phase 1 HSM                       │
│                                                                                 │
│  ┌─────────────────────────┐    ┌─────────────────────────────────────────────┐ │
│  │    Persistent Storage   │    │           Certificate Generation Job        │ │
│  │                         │    │                                             │ │
│  │  SoftHSM Token Storage  │    │  ┌─────────────────────────────────────────┐ │ │
│  │  - ReadWriteMany PV     │◄───┤  │         WebPKI Cert Generation          │ │ │
│  │  - /var/lib/softhsm/    │    │  │  - boulder-k8s:latest main container   │ │ │
│  │    tokens/              │    │  │  - debian:12 pkcs11-proxy sidecar      │ │ │
│  │  - Survives redeploys   │    │  │  - Generates keys via localhost:2345   │ │ │
│  └─────────────────────────┘    │  │  - Creates PKCS#11 configs             │ │ │
│                                 │  │  - Populates webpki-certs Secret       │ │ │
│                                 │  └─────────────────────────────────────────┘ │ │
│                                 └──────────────────┬──────────────────────────┘ │
│                                                    │                            │
│                                                    ▼                            │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                         Kubernetes Secrets                                 │ │
│  │                                                                             │ │
│  │  webpki-certs Secret:                                                       │ │
│  │  ├── int-ecdsa-a.cert.pem                                                   │ │
│  │  ├── int-ecdsa-a.pkcs11.json (points to hsm-proxy:2345)                    │ │
│  │  ├── root-rsa.cert.pem                                                      │ │
│  │  ├── root-ecdsa.cert.pem                                                    │ │
│  │  └── ... (NO private keys stored!)                                          │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                    │                            │
│                                                    ▼                            │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                        Boulder CA Services                                  │ │
│  │                                                                             │ │
│  │  ┌───────────────────────┐                ┌───────────────────────┐         │ │
│  │  │   Boulder CA Pod 1    │                │   Boulder CA Pod 2    │         │ │
│  │  │                       │                │                       │         │ │
│  │  │  ┌─────────────────┐  │                │  ┌─────────────────┐  │         │ │
│  │  │  │ boulder-k8s:    │  │                │  │ boulder-k8s:    │  │         │ │
│  │  │  │ latest          │  │                │  │ latest          │  │         │ │
│  │  │  │                 │  │                │  │                 │  │         │ │
│  │  │  │ PKCS#11 calls   │  │                │  │ PKCS#11 calls   │  │         │ │
│  │  │  │ to hsm-proxy:   │  │                │  │ to hsm-proxy:   │  │         │ │
│  │  │  │ 2345            │  │                │  │ 2345            │  │         │ │
│  │  │  └─────────────────┘  │                │  └─────────────────┘  │         │ │
│  │  └───────────────────────┘                └───────────────────────┘         │ │
│  │                │                                        │                   │ │
│  │                │                PKCS#11                 │                   │ │
│  │                └────────────── requests ─────────────────┘                   │ │
│  │                                    │                                        │ │
│  │                                    ▼                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐ │ │  
│  │  │                    Shared HSM Proxy Service                            │ │ │
│  │  │                                                                         │ │ │
│  │  │  ┌─────────────────────────────────────────────────────────────────┐   │ │ │
│  │  │  │                    HSM Proxy Pod                               │   │ │ │
│  │  │  │                                                                 │   │ │ │
│  │  │  │  ┌─────────────────────────────────────────────────────────┐   │   │ │ │
│  │  │  │  │              debian:12 Container                       │   │   │ │ │
│  │  │  │  │                                                         │   │   │ │ │
│  │  │  │  │  - pkcs11-proxy (listens on :2345)                     │   │   │ │ │
│  │  │  │  │  - SoftHSM2 backend                                     │   │   │ │ │
│  │  │  │  │  - Token storage: /var/lib/softhsm/tokens/              │   │   │ │ │
│  │  │  │  │  - Handles multiple concurrent CA requests              │   │   │ │ │
│  │  │  │  └─────────────────────────────────────────────────────────┘   │   │ │ │
│  │  │  └─────────────────────────────────────────────────────────────────┘   │ │ │
│  │  └─────────────────────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                      ▲                                           │
│                                      │                                           │
│                          Mounts shared PV:                                      │
│                          /var/lib/softhsm/tokens/                               │
└─────────────────────────────────────────────────────────────────────────────────┘

Service Communication:
- Boulder CA pods → hsm-proxy Service (ClusterIP) → HSM Proxy Pod
- HSM Proxy Pod accesses shared SoftHSM token storage via PersistentVolume
- PKCS#11 configuration points to "hsm-proxy:2345" instead of localhost
```

## Technical Specifications

### Container Configuration
- **Base Image**: `debian:12` (matches boulder-k8s:latest)
- **PKCS#11 Proxy**: Listen on `localhost:2345`
- **SoftHSM Libraries**: `apt install softhsm2` in sidecar
- **Token Storage**: `/var/lib/softhsm/tokens/` on ReadWriteMany PV

### PKCS#11 Configuration
```json
{
  "module": "hsm-proxy:2345",
  "tokenLabel": "intermediate-ca", 
  "pin": "1234",
  "privateKeyLabel": "intermediate-key"
}
```

### Volume Strategy
- **Type**: hostPath PersistentVolume (Phase 1 development)
- **Access Mode**: ReadWriteMany (shared across CA replicas)
- **Mount Path**: `/var/lib/softhsm/tokens/`
- **Persistence**: Survives redeploys, cleared by `make clean`

## Implementation Plan

### File Structure
```
k8s/
├── deployments/hsm/
│   ├── softhsm-storage.yaml          # PV + PVC for token storage
│   └── webpki-cert-generation.yaml   # Job with sidecar pattern
├── configmaps/hsm/
│   ├── pkcs11-proxy-config.yaml      # PKCS#11 proxy configuration
│   └── pkcs11-templates.yaml         # PKCS#11 config templates (localhost:2345)
└── scripts/
    ├── generate-webpki-certs.sh      # Updated to use Kubernetes Job
    └── setup-pkcs11-proxy.sh         # PKCS#11 proxy setup script
```

### Implementation Steps (Ordered)

1. **Create shared persistent volume for SoftHSM token storage**
   - `k8s/deployments/hsm/softhsm-storage.yaml`
   - hostPath PV with ReadWriteMany access

2. **Create debian:12 based pkcs11-proxy sidecar container configuration**
   - Install SoftHSM2 and pkcs11-proxy packages
   - Configure to listen on localhost:2345

3. **Create WebPKI certificate generation Job with sidecar pattern**
   - `k8s/deployments/hsm/webpki-cert-generation.yaml`
   - boulder-k8s:latest main container + debian:12 sidecar

4. **Configure PKCS#11 proxy communication**
   - Proxy listens on localhost:2345
   - Connects to SoftHSM token storage via file system

5. **Create PKCS#11 configuration templates for localhost:2345**
   - `k8s/configmaps/hsm/pkcs11-templates.yaml`
   - Point to proxy instead of direct library paths

6. **Update Boulder CA deployment with sidecar**
   - Modify `k8s/deployments/boulder/ca.yaml`
   - Add pkcs11-proxy sidecar alongside boulder-k8s main container

7. **Update certificate generation script**
   - `k8s/scripts/generate-webpki-certs.sh`
   - Create and monitor Kubernetes Job instead of direct execution

8. **Add HSM cleanup target to Makefile**
   - `make clean-hsm` deletes HSM PV and regenerates certificates

9. **Test complete sidecar workflow**
   - Proxy startup → certificate generation → CA access via proxy

10. **Update architecture documentation**
    - Document production-ready sidecar approach
    - Include Phase 2 transition path

11. **Validate end-to-end workflow**
    - Boulder CA accessing keys through PKCS#11 proxy
    - Certificate issuance functionality

## Phase 2 Transition Strategy

The sidecar architecture enables seamless Phase 2 transition:

**Phase 1 (Current)**: SoftHSM sidecar  
**Phase 2 (Future)**: Remote HSM proxy sidecar  

**Changes Required for Phase 2**:
- Replace SoftHSM sidecar with remote HSM proxy sidecar
- Update proxy configuration to connect to network HSM
- Boulder containers require **zero changes** (still call localhost:2345)

## Key Decisions Made

1. **Sidecar Pattern**: Production-ready, easier Phase 2 transition
2. **debian:12**: Consistency with boulder-k8s:latest base  
3. **localhost:2345**: Standard PKCS#11 proxy port
4. **ReadWriteMany PV**: Shared token storage across CA replicas
5. **Job-based Generation**: Kubernetes-native certificate generation
6. **No Image Modifications**: Keep boulder-k8s:latest unchanged

## Status

- ✅ **Architecture Design**: Complete
- ✅ **Technical Decisions**: Finalized  
- ✅ **Implementation Plan**: Documented
- 🔄 **Next Phase**: Ready for Code mode implementation

**Ready to proceed with implementation using Code mode.**
