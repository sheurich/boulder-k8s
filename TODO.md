# Boulder Kubernetes Deployment - TODO List

## Project Overview

This TODO list serves as the persistent task tracking system for the Boulder Kubernetes deployment project. It maintains a complete record of accomplished work, current progress, and remaining tasks organized by priority and implementation phases, aligned with the official SPEC documents.

**Last Updated**: 2025-08-18
**Project Status**: Phase 1 Complete, Phase 2 Not Started
**Current Focus**: Preparing for Phase 2 Implementation

---

## 📊 Project Progress Summary

- **Phase 1 (Initial Kubernetes Deployment)**: 100% Complete ✅
  - *See [SPECp1.md](SPECp1.md) for full details.*
- **Phase 2 (Multi-Environment & CI-Compatible Deployment)**: 0% Complete
  - *See [SPECp2.md](SPECp2.md) for full details.*

---

## ✅ Completed Work (Running Log)

### Phase 1: Initial Kubernetes Deployment *(Completed January 2025)*

- ✅ **Architecture & Design**
  - Defined Kubernetes-native service discovery strategy, replacing Consul.
  - Established container strategy using Boulder's `Containerfile`.
  - Documented service dependencies and startup sequences.

- ✅ **Kubernetes Manifests & Services**
  - Deployed all core Boulder services as Kubernetes pods (CA, RA, SA, VA, WFE2, etc.).
  - Deployed all supporting infrastructure (MariaDB, Redis, ProxySQL).
  - Converted Boulder's JSON configuration to Kubernetes ConfigMaps and Secrets.

- ✅ **PKI & Certificate Management**
  - Implemented file-based PKCS#11 configuration for the test environment.
  - Automated generation of WebPKI and internal mTLS certificate hierarchies.
  - Mounted certificates as Kubernetes Secrets.

- ✅ **Testing & Validation**
  - Implemented Kubernetes Job to run the full Boulder integration test suite.
  - Created health check scripts for all services.
  - Validated end-to-end ACME workflow.

- ✅ **Deployment & Tooling**
  - Created `deploy.sh` for one-command deployment on `kind`.
  - Developed `Makefile` with standardized targets for linting and testing.
  - Established development standards in `AGENTS.md`.

---

## 📋 Pending Tasks by Phase

### Phase 2: Multi-Environment & CI-Compatible Deployment *(Next)*

- 📋 **HSM Integration**
  - Implement network HSM architecture using `vegardit/softhsm2-pkcs11-proxy`.
  - Configure Boulder CA services to use the network HSM.
  - Set up TLS-PSK authentication and high availability for the HSM proxy.
  - **Priority**: High
  - **Dependencies**: Phase 1 complete.

- 📋 **Environment-Specific Overlays**
  - Create Kustomize overlay structure for `development`, `staging`, and `production`.
  - Define environment-specific patches for resource limits, replicas, and networking.
  - Manage environment-specific secrets and configurations.
  - **Priority**: High
  - **Dependencies**: Phase 1 complete.

- 📋 **CI/CD Workflow**
  - Implement GitHub Actions pipeline for automated testing and deployment.
  - Build and push container images to a registry.
  - Automate deployment to staging and production environments.
  - Implement rollback procedures.
  - **Priority**: Medium
  - **Dependencies**: Kustomize overlays.

- 📋 **Monitoring and Observability**
  - Deploy Prometheus and Grafana for metrics collection and visualization.
  - Configure AlertManager with rules for Boulder services.
  - Implement log aggregation with Fluentd or a similar tool.
  - **Priority**: Medium
  - **Dependencies**: Services operational.

- 📋 **Security Hardening**
  - Implement strict NetworkPolicies for service isolation.
  - Apply Pod Security Standards (PSS) or Pod Security Policies (PSP).
  - Automate secret rotation.
  - Configure audit logging.
  - **Priority**: High
  - **Dependencies**: Services operational.

- 📋 **Performance Optimization**
  - Configure Horizontal Pod Autoscalers (HPA) for key services.
  - Implement database connection pooling with PgBouncer or similar.
  - Configure Redis sharding/clustering for improved performance.
  - Tune load balancer settings for production traffic.
  - **Priority**: Medium
  - **Dependencies**: Monitoring stack deployed.

---

## 🎯 Next Steps (Immediate Actions)

1.  **Initiate Phase 2 Planning**
    - Review `SPECp2.md` with the team.
    - Break down Phase 2 deliverables into smaller, actionable tasks.
    - Prioritize the implementation of HSM integration and Kustomize overlays.

2.  **Begin HSM Integration**
    - Set up the `vegardit/softhsm2-pkcs11-proxy` service.
    - Develop the necessary Kubernetes manifests for the HSM proxy deployment.
    - Start adapting the Boulder CA configuration to use the network HSM.

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