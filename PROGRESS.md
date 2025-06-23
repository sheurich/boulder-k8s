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

## **2025-06-23 (continued)**

- **What was done:**
  - Created and applied a Service manifest for ProxySQL (`boulder-proxysql`) to match the DNS name expected by Boulder.
  - Created and applied a Service manifest for MySQL/MariaDB (`boulder-mysql`) to match the DNS name expected by Boulder.
  - Verified that the `boulder-sa-1` pod now starts and attempts to connect to both services.
  - Confirmed that the previous DNS/service name blocker is resolved.
- **What is in progress:**
  - Debugging a new application-level error: `Error 1045 (28000): Access denied for user 'sa'@'10.244.0.67' (using password: NO)` when `boulder-sa-1` attempts to connect to MySQL/MariaDB.
- **Problems or blockers:**
  - **Problem:** The Boulder application cannot authenticate to MySQL/MariaDB due to missing or incorrect credentials.
  - **Analysis:** The pod is now able to resolve and reach the database service, but the required user/password is not set or not being passed. This is likely a configuration or secret management issue.
- **Notes, context, or advice for future agents/contributors:**
  - The networking and service discovery issues are now fixed. Focus next on ensuring the correct database user and password are created and passed to the Boulder microservices, likely via Kubernetes Secrets and environment variables or mounted files.
  - Review the Boulder configuration and Kubernetes manifests for how DB credentials are set up and referenced.
  - Commit all new and changed files after this fix.

## **2025-06-23 (continued, agent update)**

- **What was done:**
  - Created a Kubernetes Secret manifest (`boulder-mysql-sa-secret.yaml`) to store the MySQL 'sa' user and password.
  - Updated the MariaDB deployment (`bmysql-deployment.yaml`) to use the secret for user/password and to create the `boulder_sa_integration` database.
  - Updated the Boulder microservice deployment (`boulder-sa-1-deployment.yaml`) to inject the same credentials from the secret as environment variables.
- **What is in progress:**
  - Apply the new secret and updated deployments:
    ```sh
    kubectl apply -f k8s/boulder-mysql-sa-secret.yaml
    kubectl apply -f k8s/bmysql-deployment.yaml
    kubectl apply -f k8s/boulder-sa-1-deployment.yaml
    ```
  - Verify that the Boulder microservice can now authenticate to MySQL/MariaDB using the provided credentials.
- **Problems or blockers:**
  - None at this step, but if authentication still fails, check that the MariaDB container creates the user with the password from the secret and that the Boulder app uses the correct environment variables.
- **Notes, context, or advice for future agents/contributors:**
  - This pattern (using Kubernetes Secrets for DB credentials) should be followed for all Boulder microservices that require database access.
  - If you need to rotate credentials, update the secret and reapply the deployments.
  - Continue rolling out and verifying the remaining Boulder microservices as described in the PRD and previous progress entries.
