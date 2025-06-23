# **Boulder Kubernetes Migration - Progress Log**

## **2025-06-23**

- **What was done:**
  - Fixed the boulder-sa-1 deployment. It now successfully runs using a distroless image and a direct binary execution, removing the need for an init container or shell.
  - Verified that mounted Kubernetes configs and secrets are correctly found by the service binary.
  - Made a key decision to resolve the current blocker by renaming the ProxySQL service rather than changing the Boulder configuration.
- **Problems or blockers:**
  - **Problem:** boulder-sa-1 is now failing with a DNS error: dial tcp: lookup boulder-proxysql on 10.96.0.10:53: no such host.
  - **Analysis:** This confirms the Boulder application is correctly configured to look for a service named boulder-proxysql, but the Kubernetes service for ProxySQL is not currently named that.
- **Notes, context, or advice for future agents/contributors:**
  - The immediate next step is to update the metadata.name field in the ProxySQL Service manifest to boulder-proxysql.
  - Once the service is renamed and reapplied, verify that the boulder-sa-1 pod can connect successfully.
  - This "direct binary execution with a distroless image" pattern is successful and should be the template for deploying the other Boulder microservices.
  - Per the previous agent's note, remember to commit all changed files after this fix.

## **2025-06-22**

- **What was done:**
  - Implemented the full Boulder microservices architecture after a deep analysis of boulder/test/startservers.py.
  - Created Kubernetes deployment manifests for the Boulder Storage Authority (boulder-sa-1, boulder-sa-2) and all three nonce-service instances.
  - Fixed a critical issue with the Redis cluster; all four instances are now fully operational with dedicated PersistentVolumeClaims (PVCs) and correct ConfigMap mounts.
  - Deployed and verified supporting services: Consul, MySQL (MariaDB), Jaeger, and PKI metal.
- **What is in progress:**
  - Creating deployment manifests for the remaining Boulder microservices (boulder-ca, boulder-ra, boulder-va, boulder-wfe2, ocsp-responder).
- **Problems or blockers:**
  - **Problem:** Boulder microservice pods fail to start because the required Go binaries are not present in the container image. The error is exec: "./bin/boulder": stat ./bin/boulder: no such file or directory.
  - **Analysis:** The original entrypoint.sh script handles the binary compilation. This step is missing in the Kubernetes deployments.
  - **Proposed Solution:** Implement an init container to compile the binaries before the main application container starts. This provides a clean separation of build and run concerns.
- **Notes, context, or advice for future agents/contributors:**
  - **Critical Insight:** Boulder is not a monolithic application. It is a complex microservice architecture. All future work must treat each component (ca, ra, va, etc.) as a separate service with its own deployment. Refer to startservers.py for service dependencies.
  - The immediate priority is to solve the binary build blocker. After that, roll out the remaining microservice deployments according to the dependency map discovered.

## **2025-06-21**

- **What was done:**
  - **Phase 1 (Inventory & Tag) Completed:** Analyzed docker-compose.yml files, identified all services, and created a structured inventory.
  - **Phase 2 (YAML Scaffold) Completed:** Used kompose to generate initial Kubernetes Deployment and Service manifests. Successfully applied the manifests to a local Minikube cluster and verified that initial pods were created.
  - **Phase 3 (Stateful Operators) Started:** Deployed MariaDB and Redis operators. Initial work on Redis cluster setup began.
  - **Phase 7 (Observability) Partially Completed:** Deployed Jaeger for tracing.
- **Problems or blockers:**
  - Initial Redis cluster deployment was unstable, with several instances failing to start due to configuration issues. This was later resolved on 2025-06-22.
- **Notes, context, or advice for future agents/contributors:**
  - The kompose output provides a good baseline but requires significant modification for a production setup, especially for stateful services and complex applications like Boulder.
