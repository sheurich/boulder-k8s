# Boulder Kubernetes Architecture Decisions

This document records key architectural decisions made for the Boulder Kubernetes implementation. These decisions serve as the canonical reference and should be cited by other documentation rather than duplicating the rationale.

## Overview

This document follows the [Architecture Decision Records (ADR)](https://adr.github.io/) format to capture important architectural decisions, their context, and rationale. Each decision includes the background, available options, chosen approach, and implications.

---

## Decision 1: OCSP Functionality Exclusion

**Status:** Accepted  
**Date:** 2025-08-19  
**Authority:** Boulder upstream deprecation policy

### Context

Boulder's upstream project has officially deprecated OCSP (Online Certificate Status Protocol) functionality and scheduled it for complete removal from the codebase.

### Decision

**EXCLUDE all OCSP-related services and functionality** from the Kubernetes implementation.

#### Excluded OCSP Services

The following Boulder OCSP services are **NOT** implemented in this Kubernetes deployment:

- **OCSP Responder** - Service that responds to OCSP status requests
- **OCSP Generator** - Service that generates OCSP responses  
- **OCSP Updater** - Service that updates OCSP response data
- **Akamai Purger** - Service for purging OCSP responses from Akamai CDN
- All OCSP-related configuration options and functionality
- All OCSP-related database tables and operations

### Rationale

1. **Deprecated Status**: OCSP functionality is officially deprecated in Boulder upstream
2. **Removal Timeline**: OCSP services are scheduled for complete removal from Boulder
3. **Modern Alternatives**: End Entity Certificate Distribution Points (CDP) and CRLSets provide more efficient revocation checking mechanisms
4. **Reduced Complexity**: Excluding OCSP simplifies the Kubernetes deployment and reduces operational overhead
5. **Future-Proofing**: Aligns with Boulder's strategic direction toward CDP and CRLSets

### Consequences

**Positive:**
- Simplified deployment architecture
- Reduced maintenance burden
- Fewer services to configure and monitor
- Alignment with Boulder's future direction

**Negative:**
- No OCSP status checking capabilities (mitigated by CDP and CRLSets)

**Impact:**
- Kubernetes manifests exclude OCSP service deployments
- Configuration files omit OCSP-related settings  
- Database initialization scripts exclude OCSP tables
- Integration tests exclude OCSP functionality validation
- Monitoring and alerting exclude OCSP metrics

**Note:** This exclusion does not affect core ACME certificate issuance functionality.

---

## Decision 2: HSM Implementation in Phase 1

**Status:** Accepted  
**Date:** 2025-08-19  
**Authority:** Development team decision

### Context

There was a conflict between [`reference/SPECp1.md`](../reference/SPECp1.md) (which deferred HSM to Phase 2) and [`architecture/phase1/hsm-implementation-plan.md`](../phase1/hsm-implementation-plan.md) (which provided detailed Phase 1 HSM implementation).

### Decision

**INCLUDE SoftHSM sidecar pattern in Phase 1** to provide complete certificate signing capabilities.

### Available Options

1. **Include HSM in Phase 1** - Implement SoftHSM sidecar with PKCS#11 proxy
2. **Defer HSM to Phase 2** - Use basic file-based certificate operations
3. **Hybrid Approach** - Include basic certificates in Phase 1, defer HSM sidecar to Phase 2

### Rationale

**Chosen: Option 1 - Include HSM in Phase 1**

1. **Existing Investment**: Detailed implementation plan indicates significant work already completed
2. **Boulder Compatibility**: File-based PKCS#11 configuration aligns with Boulder's test environment approach
3. **Complete Testing**: Provides complete certificate signing capability for integration testing
4. **Upstream Alignment**: Boulder's test environment uses local SoftHSM, making it appropriate for Phase 1
5. **Future Transition**: Sidecar pattern enables seamless Phase 2 transition to network HSM

### Implementation Approach

- **Architecture**: PKCS#11 proxy + SoftHSM sidecar pattern
- **Base Image**: debian:12 (consistent with boulder-k8s:latest)
- **Communication**: localhost:2345 PKCS#11 proxy endpoint
- **Storage**: ReadWriteMany PersistentVolume for shared token storage
- **Transition Path**: Phase 2 only requires swapping SoftHSM sidecar for network HSM proxy

### Consequences

**Positive:**
- Complete certificate signing functionality in Phase 1
- Proper Boulder HSM integration patterns established
- Future-proof architecture for Phase 2 transition
- Full integration test capability

**Negative:**
- Increased Phase 1 complexity
- Additional containers and configuration required

---

## Decision 3: mTLS Implementation in Phase 1

**Status:** Accepted  
**Date:** 2025-08-19  
**Authority:** Boulder security requirements

### Context

There was conflicting guidance on whether mTLS should be implemented in Phase 1 or deferred to Phase 2, with [`reference/SPECp1.md`](../reference/SPECp1.md) stating it was required but showing deferred implementation examples.

### Decision

**IMPLEMENT mTLS in Phase 1** as a core security requirement.

### Available Options

1. **mTLS Required in Phase 1** - Implement immediately for all inter-service communication
2. **mTLS Deferred to Phase 2** - Focus on basic security for development environment
3. **Hybrid Approach** - Prepare mTLS infrastructure but make it optional/configurable

### Rationale

**Chosen: Option 1 - mTLS Required in Phase 1**

1. **Boulder Core Requirement**: Boulder documentation explicitly states mTLS "is a core requirement for Boulder's gRPC services and cannot be disabled"
2. **Security Foundation**: Establishes proper security patterns from the start
3. **Integration Test Validity**: Ensures integration tests validate the same security model as production
4. **Architectural Consistency**: Maintains consistency with Boulder's design principles

### Implementation Approach

- **cert-manager Integration**: Automated certificate lifecycle management
- **Internal PKI**: Dedicated internal CA for service-to-service certificates
- **Certificate Automation**: Automatic certificate provisioning and renewal
- **Service Configuration**: All gRPC services configured with mTLS certificates

### Consequences

**Positive:**
- Proper Boulder security implementation
- Foundation for production security hardening
- Validates complete Boulder security model
- Automated certificate management

**Negative:**
- Increased Phase 1 complexity
- Additional certificate management overhead
- More complex service configuration

---

## Decision 4: Service Port Standardization

**Status:** Accepted  
**Date:** 2025-08-19  
**Authority:** Upstream Boulder alignment

### Context

Multiple documents showed conflicting port assignments for Boulder services, particularly the nonce service, with documentation not matching the actual Boulder source code.

### Decision

**MATCH upstream Boulder exactly** with corrected port assignments based on actual source code analysis.

### Standard Port Assignments

Based on [`vendor/github.com/letsencrypt/boulder/test/startservers.py`](../../vendor/github.com/letsencrypt/boulder/test/startservers.py):

#### Core Services
| Service | gRPC Port | Debug Port | Instances |
|---------|-----------|------------|-----------|
| **boulder-wfe2** | N/A | 8013 | 1 |
| **boulder-ra** | 9394/9494 | 8002/8102 | 2 |
| **boulder-ca** | 9393/9493 | 8001/8101 | 2 |  
| **boulder-sa** | 9395/9495 | 8003/8103 | 2 |
| **boulder-va** | 9392/9492 | 8004/8104 | 2 |
| **boulder-publisher** | 9391/9491 | 8009/8109 | 2 |

#### Nonce Service (Geographic Distribution)
| Service | gRPC Port | Debug Port | Location |
|---------|-----------|------------|----------|
| **nonce-service-taro-1** | 9301 | 8111 | Taro datacenter |
| **nonce-service-taro-2** | 9501 | 8113 | Taro datacenter |
| **nonce-service-zinc-1** | 9401 | 8112 | Zinc datacenter |

#### Remote VA Services (MPIC)
| Service | gRPC Port | Debug Port | Purpose |
|---------|-----------|------------|---------|
| **remoteva-a** | 9397 | 8011 | Multi-perspective validation |
| **remoteva-b** | 9498 | 8012 | Multi-perspective validation |
| **remoteva-c** | 9499 | 8023 | Multi-perspective validation |

### Rationale

1. **Source Code Authority**: Ports verified against actual Boulder `startservers.py` implementation
2. **Documentation Accuracy**: Corrects multiple conflicting port assignments in documentation
3. **Boulder Fidelity**: Maintains exact compatibility with upstream Boulder development environment
4. **Integration Test Compatibility**: Ensures integration tests work with correct port assignments

### Consequences

**Positive:**
- Eliminates port assignment conflicts across documentation
- Accurate reflection of upstream Boulder configuration
- Single source of truth for all service ports
- Integration test compatibility maintained

**Negative:**
- Requires updates to multiple documentation files
- More complex nonce service configuration (3 instances vs 2)

---

## Decision 5: Directory Structure Standard

**Status:** Accepted  
**Date:** 2025-08-19  
**Authority:** Project consistency

### Context

Documentation referenced both `manifests/` and `k8s/` directories, causing confusion about the actual project structure.

### Decision

**USE `k8s/` directory** as the standard for all Kubernetes manifests and related files.

### Rationale

1. **Actual Structure**: Current project structure already uses `k8s/` directory
2. **Naming Consistency**: Aligns with project name (`boulder-k8s`)
3. **Community Convention**: Avoids confusion with Kubernetes community `manifests/` patterns
4. **Path Accuracy**: Ensures documentation matches actual file locations

### Implementation

- Update all `manifests/` references to `k8s/` in documentation
- Ensure file paths match actual directory structure  
- Fix broken internal links caused by path mismatches

### Consequences

**Positive:**
- Eliminates directory reference confusion
- Documentation matches actual project structure
- Consistent naming throughout project
- Accurate file path references

**Negative:**
- Requires updates across multiple documentation files
- Potential temporary link breakage during transition

---

## Decision 6: Documentation Consolidation Strategy

**Status:** Accepted  
**Date:** 2025-08-19  
**Authority:** Documentation maintenance

### Context

The project suffered from massive document sprawl with 3 overlapping Phase 1 architecture documents (~2,300 lines total) containing redundant content and conflicting information.

### Decision

**CONSOLIDATE architecture documentation** with the following approach:

1. **Single Source of Truth**: [`reference/SPECp1.md`](../reference/SPECp1.md) remains authoritative specification
2. **Consolidated Architecture**: Merge 3 Phase 1 documents into single [`architecture/phase1.md`](phase1.md)
3. **Service Authority**: [`architecture/shared/service-matrix.md`](service-matrix.md) as single source for service definitions
4. **Unified Troubleshooting**: Merge separate troubleshooting guides into single comprehensive document

### Expected Outcomes

- **75% Reduction** in Phase 1 architecture documentation volume (~2,300 → ~580 lines)
- **Zero Conflicts** between specification and implementation documents
- **Single Authoritative Sources** for all major topics
- **Streamlined Navigation** and improved developer experience

### Content Migration Strategy

#### Preserve (Unique Content)
- Service dependency graphs and visualizations
- Operational procedures and workflows
- Advanced troubleshooting procedures
- Performance optimization guidance
- Security architecture patterns

#### Consolidate (Duplicates)
- OCSP exclusion notices (3+ instances) → Link to this document
- Service descriptions scattered across documents → Single service matrix
- Configuration examples → Consolidated in Phase 1 architecture

#### Remove (Overlapping Content)  
- Implementation guidance covered in [`reference/SPECp1.md`](../reference/SPECp1.md)
- Generic Kubernetes deployment patterns
- Directory structure examples that conflict with actual structure

### Consequences

**Positive:**
- Dramatically reduced maintenance burden
- Eliminated conflicting information
- Improved developer onboarding experience
- Single locations for updates

**Negative:**
- Temporary disruption during consolidation
- Requires careful content migration to preserve valuable information
- Link updates needed across documentation

---

## References

### Related Documents

- [`reference/SPECp1.md`](../reference/SPECp1.md) - Authoritative Phase 1 specification
- [`architecture/shared/service-matrix.md`](service-matrix.md) - Single source of truth for service definitions
- [`reference/BOULDER.md`](../reference/BOULDER.md) - Upstream Boulder technical reference
- [`CONSOLIDATION-PLAN.md`](../../CONSOLIDATION-PLAN.md) - Detailed consolidation analysis and planning

### Decision Authority

- **Technical Decisions**: Based on Boulder upstream requirements and best practices
- **Scope Decisions**: Aligned with Phase 1 development environment objectives
- **Implementation Decisions**: Driven by maintainability and developer experience goals

### Review and Updates

This document should be updated whenever new architectural decisions are made. All changes should include:
- Context and rationale for the decision
- Impact analysis
- References to relevant specifications or requirements
- Clear ownership and authority for the decision