# Boulder Kubernetes Deployment - TODO List

## Project Overview

This TODO list serves as the persistent task tracking system for the Boulder Kubernetes deployment project. It maintains a complete record of accomplished work, current progress, and remaining tasks organized by priority and implementation phases, aligned with the official SPEC documents.

**Last Updated**: 2025-08-19T20:00:00Z
**Project Status**: Phase 1 (Near Completion - 80% Complete)
**Current Focus**: Final Service Configuration (RA WebPKI Mount, CA Dependencies)

---

## 📊 Project Progress Summary

- **Phase 1 (Initial Kubernetes Deployment)**: In Progress
  - *See [reference/SPECp1.md](reference/SPECp1.md) for full details.*
- **Phase 2 (Multi-Environment & CI-Compatible Deployment)**: 0% Complete
  - *See [reference/SPECp2.md](reference/SPECp2.md) for full details.*

---

## ✅ Completed Work (Running Log)

### Phase 1: Initial Kubernetes Deployment *(In Progress)*

- ✅ **Architecture & Design**
  - Defined Kubernetes-native service discovery strategy, replacing Consul.
  - Established container strategy using Boulder's `Containerfile`.
  - Documented service dependencies and startup sequences.

- ✅ **Database Infrastructure** *(Completed August 2025)*
  - ✅ Deployed MariaDB as a Kubernetes StatefulSet.
  - ✅ Resolved MariaDB health check probes for stable operation.
  - ✅ Deployed `db-init` job to initialize the Boulder schema.
  - ✅ Confirmed all 19 required tables are created (OCSP tables excluded).

- ✅ **Documentation Organization** *(Completed August 19, 2025)*
  - ✅ Consolidated maintenance procedures and established clearer documentation boundaries
  - ✅ Updated linting workflow to use [`make lint`](Makefile) target
  - ✅ Verified kubeconform integration working properly
  - ✅ Commit: 031b9d3

---

## 📋 Pending Tasks by Phase

### Phase 1: Initial Kubernetes Deployment *(In Progress)*

- ✅ **Infrastructure Foundation** *(Completed 2025-08-19)*
  - ✅ Kind cluster operational
  - ✅ cert-manager installed and issuing all certificates successfully
  - ✅ Boulder SA deployed and serving (logs show "SERVING" state) - **CRITICAL MILESTONE**
  - ✅ Infrastructure pods running: MariaDB, Redis, ProxySQL - **ALL OPERATIONAL**
  - ✅ Database connectivity and authentication fully working
  - ✅ All mTLS certificates ready and mounted correctly

- ✅ **Infrastructure Service Configuration** *(Completed 2025-08-19)*
  - ✅ **Database**: MariaDB authentication and connectivity fully operational
  - ✅ **Cache**: Redis authentication configured and working
  - ✅ **Proxy**: ProxySQL connectivity validated through Boulder SA
  - ✅ **Priority**: COMPLETE - All infrastructure services functional

- 🔄 **Boulder Service Configuration** *(95% Complete - 2025-08-19)*
  - ✅ **RA Service**: All major configuration sections complete (service discovery, validation profiles, rate limiting, TLS, OCSP stubs)
  - 🔄 **RA WebPKI**: Single remaining issue - certificate files not accessible via mount
  - ✅ **SCT Provider Elimination**: Successfully removed separate SCT provider, CA points to RA directly
  - 🔄 **CA Dependencies**: Init container configuration propagation issue
  - 🔄 **Publisher**: Syslog configuration (lower priority)
  - ✅ **Priority**: Near complete - foundation validated by working Boulder SA
  
- 📋 **Complete Boulder Service Deployment**
  - Deploy and verify all core services: `ca`, `ra`, `va`, `wfe2`, `publisher`
  - **Priority**: High
  - **Dependencies**: Infrastructure services functional, configuration fixes applied

- 📋 **Medium Priority Improvements** *(Added 2025-08-19)*
  - **Pre-deployment Validation**: Create validation script that runs before deployment to check required tools, cluster access, and Docker images.
  - **Centralized Feature Flag Configuration**: Move Boulder feature flags from individual service configs to a centralized ConfigMap for easier management.
  - **Enhanced Health Checks**: Improve health check scripts to verify actual service health endpoints rather than just pod status.
  - **Configuration Templates**: Create environment-specific configuration templates (development, staging, production) with overlays.
  - **Better Logging Configuration**: Standardize logging configuration across all Boulder services with consistent format and levels.

- 📋 **Documentation Consistency Tasks** *(Added 2025-08-19)*
  - **Port Assignment Verification**: Audit and resolve potentially conflicting port assignments across architecture documents. Ensure single source of truth for all service ports.
    - **Priority**: Medium
    - **Scope**: Review service-matrix.md, overview.md, and SPECp1.md for port conflicts
    - **Example**: Nonce Service shows 9501, 9601, 9502, 9602 in overview.md vs 9501/9502 in service-matrix.md
  - **Replica Count Standardization**: Establish consistent replica count recommendations across all documentation.
    - **Priority**: Medium  
    - **Scope**: Review SPECp1.md, overview.md, service-matrix.md for replica inconsistencies
    - **Example**: Nonce Service shows 2 vs 4 vs 2-4 replicas across different docs
    - **Outcome**: Single authoritative source for all replica counts

- 📋 **PKI & Certificate Management**
  - Implement file-based PKCS#11 configuration for the test environment.
  - Automate generation of WebPKI and internal mTLS certificate hierarchies.
  - Mount certificates as Kubernetes Secrets.
  - **Priority**: High
  - **Dependencies**: Core services operational.

- 📋 **Testing & Validation**
  - Implement Kubernetes Job to run the full Boulder integration test suite.
  - Create health check scripts for all services.
  - Validate end-to-end ACME workflow.
  - **Priority**: Critical
  - **Dependencies**: All services deployed.

### Phase 2: Multi-Environment & CI-Compatible Deployment

- 📋 **HSM Integration**
- 📋 **Environment-Specific Overlays**
- 📋 **CI/CD Workflow**
- 📋 **Monitoring and Observability**
- 📋 **Security Hardening**
- 📋 **Performance Optimization**

---

## 🔍 Discovered Issues & Blockers

- ⏸️ **TLS Configuration Complexity**
  - An attempt to secure MariaDB connections with mTLS was reverted for Phase 1 to maintain velocity.
  - **Next Steps**: Re-evaluate and implement a simplified TLS strategy in Phase 2.

- ⏸️ **Boulder SA Operational Constraints** *(Added 2025-08-19)*
  - Boulder SA readiness probe disabled due to HTTP debug endpoint connectivity issues (gRPC health working fine)
  - Single SA replica running temporarily due to metrics conflicts
  - Incidents DB temporarily removed from Boulder SA config to resolve metrics collector duplication
  - **Next Steps**: Address readiness probe and metrics conflicts in Phase 2

---

## 🎯 Next Steps (Immediate Actions)

**CRITICAL STATUS CHECK**: Use `make status` to verify actual service health, not just pod status.

1. **Fix RA WebPKI Certificate Mount** *(Critical - Final Issue)*
   - RA service 95% complete, only WebPKI mount preventing startup
   - Files exist in `webpki-certs` secret, mount config appears correct
   - Error: `open /etc/boulder/webpki/int-ecdsa-a.cert.pem: no such file or directory`
   - **Troubleshooting needed**: Verify volume mount is working correctly

2. **Fix CA Init Container Dependencies** *(High)*
   - CA deployment init container still references old `boulder-ra-sct-provider` service
   - Kubernetes deployment spec not updating with `kubectl apply`
   - **Action needed**: Force deployment recreation or manual spec update
   - Once fixed, CA should wait for RA service correctly

3. **Complete Service Deployment Chain** *(High)*
   - Boulder SA ✅ OPERATIONAL and SERVING (validates infrastructure)
   - Sequence: SA ✅ → RA (WebPKI fix) → CA (init fix) → VA/WFE2
   - **Validation**: Use logs to verify "SERVING" state, not just pod status
   - **End goal**: Full ACME workflow operational

---

## 🔄 Maintenance

**For complete maintenance procedures including task status indicators, weekly reviews, and update guidelines, see [`AGENTS.md`](AGENTS.md).**
