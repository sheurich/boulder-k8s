# Boulder on Kubernetes - Agent Handoff

**Project:** A production-grade implementation of the Boulder CA running on Kubernetes.

**Checkpoint:** 2025-08-19T17:04:00.000Z

**Status:**

- **Phase 1: Infrastructure Deployment (COMPLETE)**:
  - ✅ Kubernetes cluster is running (`make setup`).
  - ✅ Database infrastructure (MariaDB, Redis, ProxySQL) is deployed and healthy.
  - ✅ Boulder database schema is initialized.
  - ✅ cert-manager deployed with proper RBAC permissions and working certificates.
  - ✅ mTLS certificates generated and ready for all Boulder services.
  - ✅ Boulder Docker image built (`boulder-k8s:latest`) and loaded into cluster.
  - ✅ Database authentication RESOLVED - Boulder SA connects successfully.
  - ✅ Boulder SA service is running and fully operational.

- **Documentation Organization (COMPLETE)**:
  - ✅ Consolidated maintenance procedures in [`AGENTS.md`](AGENTS.md) into dedicated section
  - ✅ Established clearer boundaries between [`AGENTS.md`](AGENTS.md) and [`README.md`](README.md)
  - ✅ Updated linting documentation to reference [`make lint`](Makefile) target
  - ✅ Verified kubeconform integration working properly (commit 031b9d3)
  - ✅ All linting checks pass including kubeconform validation

---

## 🚀 Immediate Task: Deploy Remaining Boulder Services

Your immediate task is to **deploy the remaining Boulder services** (CA, RA, VA, WFE2, Publisher) now that the infrastructure and Boulder SA are operational, then set up mTLS for Boulder SA -> ProxySQL -> MariaDB as requested.

**Recent Progress**: Documentation organization has been completed with improved maintenance procedures and clearer boundaries between user and developer documentation.

**System Status Check:**

```sh
kubectl get pods -n boulder
# Boulder SA should be Running and Ready
```

---

## 📝 Project Context

**Implementation Status:**

Phase 1 infrastructure is **COMPLETE** and operational. Boulder SA service is running and connecting successfully to MariaDB through ProxySQL.

**Key Architectural Decisions:**

- **mTLS Required:** Service-to-service communication uses cert-manager-issued certificates
- **OCSP Excluded:** All OCSP functionality is intentionally excluded (deprecated in Boulder)
- **Single SA Replica:** Running 1 replica temporarily due to metrics conflicts

**Current Foundation:** All infrastructure services (MariaDB, Redis, ProxySQL, cert-manager) and Boulder SA are operational and ready for remaining Boulder services.

---

## 📚 Essential Documentation

**Required Reading:**
- [`reference/SPECp1.md`](reference/SPECp1.md) - Phase 1 specification and success criteria
- [`architecture/shared/service-matrix.md`](architecture/shared/service-matrix.md) - Service specifications and configuration
- [`TODO.md`](TODO.md) - Current project status and task prioritization

**Additional References:** See [`README.md`](README.md) for complete documentation index.

---

## ✅ Task Details & Success Criteria

**What Needs to Be Done:**

1. **Deploy remaining Boulder services**: CA, RA, VA, WFE2, Publisher services using the working Boulder SA as foundation
2. **Set up mTLS**: Configure mTLS for Boulder SA -> ProxySQL -> MariaDB as requested by user
3. **Run validation**: Execute health checks and integration test suite
4. **Address readiness probe**: Fix HTTP debug endpoint connectivity for proper health checking

**Success Criteria:**

- ✅ Boulder SA pods connect successfully to MariaDB through ProxySQL (COMPLETE)
- All Boulder service pods in the `boulder` namespace are in the `Running` or `Completed` state  
- `make health-check` passes for all Boulder services
- `make test` (integration tests) passes successfully
- mTLS configured for database connections

---

## 🚀 Next Steps

1. **Deploy Remaining Boulder Services:**
   ```sh
   # Deploy CA service (depends on SA)
   kubectl apply -f k8s/deployments/boulder/ca.yaml
   
   # Deploy RA service (depends on SA, CA)  
   kubectl apply -f k8s/deployments/boulder/ra.yaml
   
   # Deploy VA service (depends on SA)
   kubectl apply -f k8s/deployments/boulder/va.yaml
   
   # Deploy WFE2 service (depends on SA, RA)
   kubectl apply -f k8s/deployments/boulder/wfe2.yaml
   
   # Deploy Publisher service (depends on SA)
   kubectl apply -f k8s/deployments/boulder/publisher.yaml
   ```

2. **Configure mTLS for Database:**
   ```sh
   # Boulder SA -> ProxySQL -> MariaDB mTLS setup
   # Update ProxySQL configuration to use TLS
   # Configure Boulder SA to use client certificates for database connections
   ```

3. **Validation:**
   ```sh
   make health-check
   make test
   ```

---

## ⚠️ Known Issues & Troubleshooting

**Current Known Issues:**
1. **HTTP Debug Endpoint**: Boulder SA readiness probe disabled due to debug server connectivity issues (gRPC health working fine)
2. **Incidents DB**: Temporarily removed from Boulder SA config to resolve metrics collector duplication
3. **Single Replica**: Boulder SA running with 1 replica to avoid metrics conflicts

**Major Issues RESOLVED This Session:**
- ✅ **Database Authentication**: ProxySQL environment variable substitution fixed
- ✅ **Boulder SA Connectivity**: Successfully connecting to MariaDB through ProxySQL
- ✅ **gRPC Services**: StorageAuthority and StorageAuthorityReadOnly services serving
- ✅ **Syslog Configuration**: Fixed container startup failures
- ✅ **Metrics Conflicts**: Resolved by removing incidents DB and using single replica

**Troubleshooting Commands:**
- **Check pod status:** `kubectl get pods -n boulder -o wide`
- **Check SA logs:** `kubectl logs -l app=boulder-sa -n boulder`
- **Check ProxySQL connectivity:** `kubectl exec [proxysql-pod] -n boulder -- mysql -u boulder -pboulder-db-password -h 127.0.0.1 -P 6033 -e "SELECT 1;"`
- **Check certificates:** `kubectl get certificates -n boulder` (should all be Ready=True)
- **Check database connectivity:** `kubectl exec mariadb-0 -n boulder -- mysql -u boulder -pboulder-db-password -e "SELECT 1;"`

**Current Status:** Infrastructure complete and Boulder SA operational. Documentation organization completed (commit 031b9d3). Ready to deploy remaining Boulder services and configure mTLS.

**Repository Status:**
- **Current Branch**: augv2
- **Recent Commit**: 031b9d3 - "docs: consolidate maintenance procedures and establish clearer documentation boundaries"
- **Next Agent Tasks**: Continue with Boulder service deployment (CA, RA, VA, WFE2, Publisher) and mTLS configuration
