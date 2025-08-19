# Boulder on Kubernetes - Agent Handoff

**Project:** A production-grade implementation of the Boulder CA running on Kubernetes.

**Checkpoint:** 2025-08-19T03:05:00.000Z

**Status:**

- **Phase 1: Infrastructure Deployment (Nearly Complete)**:
  - ✅ Kubernetes cluster is running (`make setup`).
  - ✅ Database infrastructure (MariaDB, Redis, ProxySQL) is deployed and healthy.
  - ✅ Boulder database schema is initialized.
  - ✅ cert-manager deployed with proper RBAC permissions and working certificates.
  - ✅ mTLS certificates generated and ready for all Boulder services.
  - ✅ Boulder Docker image built (`boulder-k8s:latest`) and loaded into cluster.
  - ✅ Boulder SA service can now start (TLS and logging issues resolved).
  - 🔄 Database authentication issue preventing SA from connecting to MariaDB.

---

## 🚀 Immediate Task: Fix Database Authentication for Boulder SA

Your immediate task is to **resolve the database authentication issue** where ProxySQL is denying access for the 'boulder' user, then complete the Boulder service startup validation.

**Current Issue:**
```
boulder-sa: [AUDIT] While initializing dbMap: Error 1045 (28000): ProxySQL Error: Access denied for user 'boulder'@'10.244.1.22' (using password: YES)
```

**System Status Check:**

```sh
kubectl get pods -n boulder
kubectl logs -l app=boulder-sa -n boulder
```

---

## 📝 Project Context

**Implementation Status:**

The foundational infrastructure is complete and operational. Major progress in this session:
- ✅ **cert-manager Setup**: Deployed cert-manager with correct RBAC permissions including leases access
- ✅ **TLS Certificate Infrastructure**: All Boulder service certificates (SA, CA, RA, VA, WFE2, Publisher) are issued and ready
- ✅ **Boulder Image**: Built `boulder-k8s:latest` image and loaded into kind cluster  
- ✅ **Configuration Fixes**: Removed deprecated `CheckCertificateBySerial` feature flag from SA config
- ✅ **Logging Configuration**: Fixed syslog issues by disabling syslog (-1) and using stdout logging
- ✅ **Deployment Dependencies**: Fixed deployment script ordering so cert-manager deploys before Boulder services

**Current Issue:** Boulder SA can start but fails database authentication - ProxySQL denying 'boulder' user access.

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

1. **Fix Database Authentication**: Resolve ProxySQL authentication issue for 'boulder' user
2. **Verify Boulder SA startup**: Ensure SA pods can connect to database and become ready
3. **Deploy remaining Boulder services**: CA, RA, VA, WFE2, Publisher services  
4. **Run validation**: Execute health checks and integration test suite

**Success Criteria:**

- Boulder SA pods connect successfully to MariaDB through ProxySQL
- All pods in the `boulder` namespace are in the `Running` or `Completed` state
- `make health-check` passes for all Boulder services
- `make test` (integration tests) passes successfully

---

## 🚀 Next Steps

1.  **Investigate Database Authentication:**
    ```sh
    # Check ProxySQL configuration
    kubectl logs -l app=proxysql -n boulder
    kubectl get configmap proxysql-config -n boulder -o yaml
    
    # Check database credentials
    kubectl get secret db-credentials -n boulder -o yaml
    ```

2.  **Possible Solutions:**
    ```sh
    # Option 1: Check if ProxySQL has correct boulder user configured
    # Option 2: Verify database credentials match ProxySQL config
    # Option 3: Check if ProxySQL users table needs boulder user entry
    ```

3.  **Once SA is healthy:**
    ```sh
    # Continue with remaining Boulder service deployment
    make deploy  # or deploy remaining services manually
    make health-check
    make test
    ```

---

## ⚠️ Known Issues & Troubleshooting

**Current Known Issues:**
1. **Database Authentication**: ProxySQL denying 'boulder' user access - credentials or user configuration mismatch
2. **Deployment Script Dependencies**: Fixed - cert-manager now deploys before Boulder services
3. **Boulder Image**: Fixed - using `boulder-k8s:latest` instead of `boulder:latest`

**Troubleshooting Commands:**
- **Check pod status:** `kubectl get pods -n boulder -o wide`
- **Check SA logs:** `kubectl logs -l app=boulder-sa -n boulder`
- **Check ProxySQL logs:** `kubectl logs -l app=proxysql -n boulder`
- **Check certificates:** `kubectl get certificates -n boulder` (should all be Ready=True)
- **Check database connectivity:** `kubectl exec -it mariadb-0 -n boulder -- mysql -u root -p`

**Major Issues Resolved This Session:**
- ✅ cert-manager RBAC permissions (added leases access)
- ✅ All Boulder service TLS certificates issued and ready
- ✅ Boulder image built and loaded (`boulder-k8s:latest`)
- ✅ SA configuration (removed deprecated `CheckCertificateBySerial`)
- ✅ Logging configuration (disabled syslog, enabled stdout)
- ✅ Deployment dependencies (cert-manager first)

**Current Status:** Infrastructure complete, SA can start but database authentication failing. Very close to fully operational.
