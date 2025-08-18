# Boulder Kubernetes Deployment - TODO List

## Project Overview

This TODO list serves as the persistent task tracking system for the Boulder Kubernetes deployment project. It maintains a complete record of accomplished work, current progress, and remaining tasks organized by priority and implementation phases, aligned with the official SPEC documents.

**Last Updated**: 2025-08-18
**Project Status**: Phase 1 (In Progress)
**Current Focus**: Deploying Boulder Core Services

---

## 📊 Project Progress Summary

- **Phase 1 (Initial Kubernetes Deployment)**: In Progress
  - *See [SPECp1.md](SPECp1.md) for full details.*
- **Phase 2 (Multi-Environment & CI-Compatible Deployment)**: 0% Complete
  - *See [SPECp2.md](SPECp2.md) for full details.*

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

---

## 📋 Pending Tasks by Phase

### Phase 1: Initial Kubernetes Deployment *(Next)*

- 🔄 **Deploy Boulder Services**
  - Deploy core services: `sa`, `ca`, `ra`, `va`, `wfe2`.
  - **Priority**: Critical
  - **Dependencies**: Database operational.

- 📋 **Deploy Supporting Services**
  - Deploy Redis and ProxySQL.
  - **Priority**: High
  - **Dependencies**: Core services operational.

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

---

## 🎯 Next Steps (Immediate Actions)

1.  **Deploy Core Boulder Services**
    - Apply the Kubernetes manifests for `sa`, `ca`, `ra`, `va`, and `wfe2`.
    - Verify that all services start correctly and can connect to the database.

2.  **Deploy Redis and ProxySQL**
    - Apply the manifests for the remaining supporting infrastructure.
    - Ensure they are correctly configured and integrated with the Boulder services.

---

## 🔄 Review and Maintenance

### Weekly Reviews *(Every Monday)*
- Update task status and completion dates.
- Assess priority changes and blockers.
- Review completed work and lessons learned.
- Plan upcoming week's focus areas.

### Task Status Indicators
- ✅ **Completed** - Work finished and validated.
- 🔄 **In Progress** - Currently being worked on.
- 🔴 **Critical/Urgent** - High priority, blocking other work.
- ⏸️ **Blocked** - Waiting on dependencies or decisions.
- 📋 **Pending** - Planned but not yet started.