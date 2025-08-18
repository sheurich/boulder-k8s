# Boulder on Kubernetes - Agent Handoff

**Project:** A production-grade implementation of the Boulder CA running on Kubernetes.

**Checkpoint:** 2025-08-18T13:47:30.036Z

**Status:**
- **Phase 1: Infrastructure Deployment (In Progress)**:
  - ✅ Database infrastructure is operational.
  - 📋 Boulder core services deployment is pending.

---

## 🚀 Quick Start

Your immediate task is to **deploy the Boulder core services**. This involves deploying the Service orchestrator, Certificate Authority, Registration Authority, Validation Authority, and the Web Frontend.

**First Commands to Run:**
```bash
make deploy-boulder
```

---

## 📝 Project Context

**Implementation Status:**
- The Kind cluster is running and accessible.
- MariaDB is deployed and the Boulder schema is initialized (19 tables, OCSP tables excluded).
- The database initialization job completed successfully.

**Recent Accomplishments:**
- ✅ **Fixed MariaDB Health Probes:** Resolved startup and liveness probe failures, ensuring stable database operation.
- ✅ **Initialized Boulder Schema:** Successfully ran the `db-init` job to prepare the database for Boulder services.
- ✅ **Disabled TLS for Phase 1:** Reverted an attempt to implement mTLS for database connections to simplify the initial deployment. This will be revisited in a later phase.

**Outstanding Issues/Blockers:**
- **TLS Complexity:** The initial attempt to secure MariaDB with TLS introduced significant complexity. This has been deferred to a later phase to avoid blocking core service deployment.

---

## 📚 Essential Documentation

This `PROMPT.md` is your primary starting point. For deeper dives, refer to these key documents:

- **[`AGENTS.md`](AGENTS.md)**: **REQUIRED READING.** Outlines development standards, commit guidelines, and handoff protocols.
- **[`SPECp1.md`](SPECp1.md)**: Defines the completed Phase 1 requirements. Use for validation context.
- **[`SPECp2.md`](SPECp2.md)**: Defines the upcoming Phase 2 requirements.
- **[`README.md`](README.md)**: Provides a general project overview, setup instructions, and usage.
- **[`TODO.md`](TODO.md)**: Tracks detailed task status and project history.

---

## 📦 Repository Status

- **Branch:** `main`
- **Last Commit:** `fix(k8s): resolve MariaDB health check probes and database initialization`
- **Working Tree:** Clean. No uncommitted changes.

---

## 🛠️ Environment Setup

**Prerequisites:**
- [x] `git`
- [x] `make`
- [x] `docker`
- [x] `kubectl`
- [x] `kind`
- [x] `helm`
- [x] `brew` (for macOS package management)

**Quick Setup:**
1. **Install Tools:**
   ```bash
   brew bundle install
   ```
2. **Set up Local Cluster:**
   ```bash
   make setup
   ```

---

## ✅ Current Task Details

**Next Task: Deploy Boulder Services**

**What Needs to Be Done:**
1.  Deploy the core Boulder services: `sa`, `ca`, `ra`, `va`, `wfe2`.
2.  Deploy Redis and ProxySQL.
3.  Run integration tests to validate the full Boulder stack.

**Success Criteria:**
- `make deploy-boulder` completes without errors.
- All Boulder services are running and healthy in the `boulder` namespace.
- `make test` passes successfully.

**Known Issues to Watch For:**
- **Service Dependencies:** Boulder services have a strict startup order. Ensure the database is healthy before deploying the core services.

---

## 🚀 Deployment Instructions

**Step-by-Step Deployment:**
1.  **Verify Cluster Status:**
    ```bash
    kubectl get nodes
    ```
2.  **Deploy Boulder Services:**
    ```bash
    make deploy-boulder
    ```
3.  **Check deployment status:**
    ```bash
    kubectl get pods -n boulder
    ```
    *Wait for all pods to be in the `Running` or `Completed` state.*

**Validation Commands:**
- **Run integration tests:**
  ```bash
  make test
  ```
- **Perform a health check:**
  ```bash
  make health-check
  ```

---

## ⚠️ Important Notes

- **OCSP Exclusion:** This implementation **intentionally excludes** all OCSP-related functionality, as it is deprecated in the core Boulder software. Do not attempt to implement or test OCSP services.
- **Phase Boundaries:** Project phases are strictly defined by `SPECp1.md` and `SPECp2.md`. Do not begin Phase 2 work until Phase 1 is fully validated.
- **Version Control:** All changes must follow the commit conventions outlined in `AGENTS.md`. Create logical, atomic commits for all work.