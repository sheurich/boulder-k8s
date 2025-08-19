# Boulder Kubernetes Deployment - TODO List

## Project Overview

This TODO list serves as the persistent task tracking system for the Boulder Kubernetes deployment project. It maintains a complete record of accomplished work, current progress, and remaining tasks organized by priority and implementation phases, aligned with the official SPEC documents.

**Last Updated**: 2025-08-19
**Project Status**: Phase 1 (In Progress)
**Current Focus**: Deploying Boulder Core Services

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
  - ✅ Boulder SA deployed and serving (logs show "SERVING" state)
  - ✅ Infrastructure pods running: MariaDB, Redis, ProxySQL

- 🔄 **Fix Infrastructure Service Configuration** *(Critical - In Progress)*
  - **Database Issues**: MariaDB access denied - authentication/configuration problems
  - **Cache Issues**: Redis requiring authentication - configuration missing
  - **Proxy Issues**: ProxySQL connectivity untested
  - **Priority**: Critical (blocking all Boulder services)
  - **Status**: Only pods running, services not functionally working

- 🔴 **Fix Boulder Service Deployment Issues** *(Critical)*
  - **RA Service**: Configuration error "unknown field clientCertificate"
  - **Publisher Service**: Syslog connection failures (containerization issue)
  - **CA/VA/WFE2**: Waiting for dependent services to be operational
  - **Priority**: Critical
  - **Current State**: Most services in CrashLoopBackOff or Init states
  
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

1. **Fix Infrastructure Service Authentication** *(Critical)*
   - Resolve MariaDB authentication issues preventing database access
   - Configure Redis authentication to allow Boulder service connections
   - Test ProxySQL connectivity and database proxy functionality

2. **Fix Boulder Service Configuration Errors** *(Critical)*
   - Fix RA service "unknown field clientCertificate" configuration error
   - Resolve Publisher syslog connection issues for containerized environment
   - Configure CA service to use RA directly for SCT operations (no separate SCT provider needed)

3. **Complete Service Deployment Chain** *(High)*
   - Ensure proper dependency ordering between CA and RA services
   - Verify all services reach "SERVING" state (check logs, not just pod status)
   - Test end-to-end service connectivity

---

## 🔄 Maintenance

**For complete maintenance procedures including task status indicators, weekly reviews, and update guidelines, see [`AGENTS.md`](AGENTS.md).**
