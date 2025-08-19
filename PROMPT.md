# Boulder on Kubernetes - Agent Handoff

**Project:** A production-grade implementation of the Boulder CA running on Kubernetes.

**Checkpoint:** 2025-08-19T10:00:00.000Z

**Status:**

- **Phase 1: Infrastructure Deployment (Partially Complete)**:
  - ✅ Kubernetes cluster is running (`make setup`).
  - ✅ Database infrastructure (MariaDB, Redis, ProxySQL) is deployed and healthy.
  - ✅ Boulder database schema is initialized.
  - 📋 Boulder core application services deployment is pending.

---

## 🚀 Immediate Task: Deploy Boulder Applications and Validate

Your immediate task is to **deploy the remaining Boulder application services** and run the full integration test suite to validate the entire system.

**First Command to Run:**

```sh
make deploy
```

This will execute the script at `k8s/scripts/deploy.sh` to bring up all services in the correct order.

---

## 📝 Project Context

**Implementation Status:**

The foundational infrastructure is stable. The last session focused on resolving health check issues with MariaDB and ensuring the database schema was correctly initialized. The project is now ready for the application layer.

**Guiding Specification:**

The goal for this phase is defined in `reference/SPECp1.md`. The primary objective is to achieve functional parity with the upstream Boulder `docker-compose` environment. Success is measured by the passing of the full integration test suite.

**Key Architectural Decisions:**

- **mTLS Required:** As noted in `reference/SPECp1.md`, mTLS for service-to-service communication is a core Boulder requirement and is implemented in Phase 1 using cert-manager.
- **OCSP Excluded:** This implementation intentionally excludes all OCSP-related functionality, a critical constraint detailed in both the `README.md` and `AGENTS.md`.

---

## 📚 Essential Documentation

- **`reference/SPECp1.md`**: **REQUIRED READING.** Defines the "definition of done" for the current phase.
- **`README.md`**: General project overview, setup, and manual testing instructions.
- **`Makefile`**: Defines all high-level commands (`deploy`, `test`, `clean`).
- **`AGENTS.md`**: Outlines development standards and commit guidelines.

---

## ✅ Task Details & Success Criteria

**What Needs to Be Done:**

1.  Execute the deployment of all Boulder application services.
2.  Verify all pods are running and healthy.
3.  Run the full test suite to validate the end-to-end ACME workflow.

**Success Criteria:**

- `make deploy` completes without errors.
- All pods in the `boulder` namespace are in the `Running` or `Completed` state.
- `make test` (which runs both health checks and integration tests) passes successfully.

---

## 🚀 Step-by-Step Instructions

1.  **Deploy All Services:**
    ```sh
    make deploy
    ```
2.  **Validate the Deployment:**
    ```sh
    make test
    ```

---

## ⚠️ Contingency Plan

- **If `make deploy` fails:**
  1. Run `kubectl get pods -n boulder -o wide` to check pod statuses.
  2. Examine the logs of any pods that are in a `CrashLoopBackOff` or `Error` state using `kubectl logs -n boulder <pod-name>`.
  3. Consult `reference/TROUBLESHOOTING.md` for common issues.
- **If `make test` fails:**
  1. Review the test logs to identify the failing test case.
  2. Examine the logs of the relevant Boulder service(s) for errors that occurred during the test run.
  3. Consult `reference/TROUBLESHOOTING.md` for common test failures.
