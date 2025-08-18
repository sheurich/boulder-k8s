# Boulder on Kubernetes - Agent Handoff

**Project:** A production-grade implementation of the Boulder CA running on Kubernetes.

**Checkpoint:** 2025-08-18T11:30:30.939Z

**Status:**
- **Phase 1: Documentation & Setup**: 100% Complete
- **Phase 2: Deployment & Validation**: 0% Complete

---

## 🚀 Quick Start

Your immediate task is to **deploy and validate the Phase 1 implementation**. This involves setting up the local Kubernetes cluster, deploying all manifests, and running integration tests to confirm functionality.

**First Commands to Run:**
```bash
make setup
make deploy
make test
```

---

## 📝 Project Context

**Implementation Status:**
- All Phase 1 Kubernetes manifests are created and located in the `k8s/` directory.
- All necessary configuration files, including `kind-config.yaml` and `.yamllint`, are in place.
- Documentation is complete, including `README.md`, `AGENTS.md`, and architectural diagrams.

**Recent Accomplishments:**
- ✅ Completed all Phase 1 deliverables as per `SPECp1.md`.
- ✅ Consolidated and cleaned up all project documentation.
- ✅ Established and documented version control practices in `AGENTS.md`.

**Outstanding Issues/Blockers:**
- None. The project is ready for Phase 1 validation.

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
- **Last Commit:** `docs: create agent handoff system`
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

**Next Task: Deploy and Validate Phase 1**

**What Needs to Be Done:**
1.  Deploy all Kubernetes resources for the Boulder CA.
2.  Run the complete integration test suite to validate the deployment.
3.  Document the results and confirm that all Phase 1 acceptance criteria are met.

**Success Criteria:**
- `make deploy` completes without errors.
- `make test` passes successfully.
- All Boulder services are running and healthy in the `boulder` namespace.
- The local environment can successfully issue a test certificate.

**Known Issues to Watch For:**
- **Service Dependencies:** Boulder services have a strict startup order. The `db-init` job must complete successfully before other services can start.
- **DNS Propagation:** Local DNS resolution within the Kind cluster can sometimes be slow. Tests may fail intermittently if services cannot resolve each other.

---

## 🚀 Deployment Instructions

**Step-by-Step Deployment:**
1.  **Start the local cluster:**
    ```bash
    make setup
    ```
2.  **Deploy all resources:**
    ```bash
    make deploy
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