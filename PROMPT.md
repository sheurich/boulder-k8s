# Boulder on Kubernetes - Agent Handoff

**Project:** A production-grade implementation of the Boulder CA running on Kubernetes.

**Checkpoint:** 2025-08-19T02:15:00.000Z

**Status:**

- **Phase 1: Infrastructure Deployment (Nearly Complete)**:
  - ✅ Kubernetes cluster is running (`make setup`).
  - ✅ Database infrastructure (MariaDB, Redis, ProxySQL) is deployed and healthy.
  - ✅ Boulder database schema is initialized.
  - ✅ cert-manager deployed with proper RBAC permissions.
  - ✅ mTLS certificates generated for all Boulder services.
  - ✅ Boulder Docker image built and loaded into cluster.
  - ✅ All Boulder services deployed with correct configuration.
  - 🔄 Boulder services starting up (SA configuration resolved, deployment stabilizing).

---

## 🚀 Immediate Task: Complete Boulder Service Startup and Validate

Your immediate task is to **complete the Boulder service startup** and run the full integration test suite to validate the entire system.

**System Status Check:**

```sh
make status
kubectl get pods -n boulder
```

---

## 📝 Project Context

**Implementation Status:**

The foundational infrastructure is complete and operational. The last session successfully:
- Implemented mTLS with cert-manager for all Boulder gRPC services
- Resolved Boulder SA configuration issues (removed deprecated feature flags)
- Configured infrastructure services (Redis Phase 1 without TLS, ProxySQL, MariaDB) 
- Built and deployed Boulder application services

**Current Issue:** Boulder service pods are in various startup states. The SA (Storage Authority) had configuration issues that were resolved, but deployments need to fully stabilize.

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

1.  Verify Boulder service pods stabilize and reach Running state.
2.  Troubleshoot any remaining deployment or configuration issues.
3.  Run the full test suite to validate the end-to-end ACME workflow.

**Success Criteria:**

- All pods in the `boulder` namespace are in the `Running` or `Completed` state.
- `make health-check` passes for all Boulder services.
- `make test` (which runs both health checks and integration tests) passes successfully.

---

## 🚀 Next Steps

1.  **Check Current Status:**
    ```sh
    kubectl get pods -n boulder
    make health-check
    ```
2.  **If Boulder services need help:**
    ```sh
    # Check logs for any failing pods
    kubectl logs -l app=boulder-sa -n boulder
    # Delete pods if needed to force restart with correct image
    kubectl delete pods -l app=boulder-sa -n boulder
    ```
3.  **Once healthy, run integration tests:**
    ```sh
    make test
    ```

---

## ⚠️ Known Issues & Troubleshooting

**Current Known Issues:**
1. **Boulder SA deployment stabilization:** The SA pods may take several restarts to fully stabilize after configuration changes.
2. **Image pull policy:** Ensure all Boulder services are using `boulder-k8s:latest` image (not `boulder:latest`).

**Troubleshooting Commands:**
- **Check pod status:** `kubectl get pods -n boulder -o wide`
- **Check logs:** `kubectl logs -l app=boulder-sa -n boulder`
- **Force pod restart:** `kubectl delete pods -l app=boulder-sa -n boulder`
- **Check certificates:** `kubectl get certificates -n boulder`
- **Health check:** `make health-check`

**Previous Session Progress:**
- Infrastructure (MariaDB, Redis, ProxySQL): ✅ All healthy
- cert-manager and TLS certificates: ✅ Working
- Boulder image and deployments: ✅ Applied  
- Configuration issues: ✅ Resolved (SA config fixed)

The system is very close to fully operational - mainly need Boulder service startup completion.
