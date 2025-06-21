This document provides a comprehensive, machine-readable plan for migrating the Boulder project from Docker Compose to a production-ready Kubernetes environment. Each phase is defined with clear goals, inputs, tasks, and deliverables, intended to be used by autonomous agents for execution and tracking.

### **Phase 1: Inventory & Tag**

- **Goal:** Create a complete and structured inventory of all application components from the existing Docker Compose setup to inform the Kubernetes migration.
- **Status:** Not Started
- **Inputs:**
  - `boulder/docker-compose.yml`
  - `boulder/docker-compose.next.yml`
  - `boulder/start.py`
  - `boulder/test/certs/generate.sh`
  - `boulder/docs/` directory
- **Tasks:**

1.  **Setup Environment:**

- `gh repo clone letsencrypt/boulder` and navigate to the `boulder` directory.
- `docker compose build --pull`
- `./t.sh --lints`
  (The full `./t.sh` script is comprehensive but takes a long time to run, so it is not included here.)

2.  **Parse Compose Files:** Systematically parse `docker-compose.yml` and `docker-compose.next.yml`.
3.  **Extract Service Details:** For each service, extract the image, ports, volumes, networks, environment variables, `depends_on` clauses, and command/entrypoint.
4.  **Identify Stateful Services:** Flag services with persistent volume mounts (e.g., `mariadb`, `redis`) as `stateful`.
5.  **Identify Initialization Logic:** Analyze `start.py` and other scripts to determine which services require pre-start initialization (e.g., database setup, PKI generation). Tag these as `needs-init`.
6.  **Tag Services:** Assign functional tags to each service (e.g., `service:boulder-ra`, `type:microservice`, `role:database`, `role:cache`).
7.  **Review Documentation:** Scan the `docs/` directory for any non-obvious configurations, custom port usage, or operational procedures.

- **Deliverables:**
  - `compose-inventory.csv`: A CSV file detailing each service and its configuration.
  - `tags.json`: A JSON file mapping service names to their functional tags.

### **Phase 2: YAML Scaffold**

- **Goal:** Generate initial Kubernetes manifests and confirm that all services can start in a local cluster.
- **Status:** Not Started
- **Inputs:**
  - `docker-compose.yml`
  - `docker-compose.next.yml`
  - `compose-inventory.csv` (from Phase 1)
- **Tasks:**
  1.  **Execute Kompose:** Run `kompose convert` against the Docker Compose files to generate baseline Kubernetes YAML manifests.
  2.  **Review Manifests:** Compare the generated `Deployment` and `Service` manifests with `compose-inventory.csv` to ensure all ports, environment variables, and basic settings are correctly translated.
  3.  **Setup Local Cluster:** Provision a local Kubernetes cluster using `kind` or `minikube`.
  4.  **Apply Manifests:** Apply the generated YAML files to the local cluster using `kubectl apply -f .`.
  5.  **Verify Pod Status:** Check that all pods are created and reach a `Running` state without crash-looping (`kubectl get pods -w`).
- **Deliverables:**
  - A directory of raw Kubernetes `Deployment` and `Service` YAML files for each application component.

### **Phase 3: Stateful Operators**

- **Goal:** Replace the basic stateful service deployments with robust, operator-managed instances for MariaDB and Redis.
- **Status:** Not Started
- **Inputs:**
  - YAML manifests from Phase 2.
  - `sa/db/boulder_sa/` schema files.
- **Tasks:**
  1.  **Install MariaDB Operator:** Deploy a stable MariaDB Operator into the cluster.
  2.  **Define MariaDB Resource:** Create a `MariaDB` Custom Resource (CR) manifest. Configure it with storage requirements (PVCs), version, and initial user/database settings based on the inventory.
  3.  **Install Redis Operator:** Deploy a stable Redis Operator (e.g., one that supports Sentinel for high availability).
  4.  **Define Redis Resource:** Create a `Redis` Custom Resource (CR) manifest, specifying the version and storage needs.
  5.  **Deploy Resources:** Apply the CR manifests to the cluster.
  6.  **Verify Health:** Confirm that the operators have successfully deployed MariaDB and Redis pods and that they report a healthy status.
  7.  **Test Persistence:** Connect to the database and cache, write sample data, trigger a pod restart (`kubectl delete pod <pod-name>`), and verify that the data persists after the pod is recreated.
- **Deliverables:**
  - `mariadb-instance.yaml`: The `MariaDB` Custom Resource manifest.
  - `redis-instance.yaml`: The `Redis` Custom Resource manifest.
  - Updated Helm/Kustomize base including the operators as dependencies.

### **Phase 4: Secrets & PKI**

- **Goal:** Secure pod-to-pod communication with mTLS and manage all secrets, including the complex PKI bootstrapping process, using Kubernetes-native patterns.
- **Status:** Not Started
- **Inputs:**
  - `test/certs/generate.sh`
  - `Deployment` manifests from Phase 2.
- **Tasks:**
  1.  **Deploy Cert-Manager:** Install `cert-manager` into the cluster to manage the lifecycle of TLS certificates.
  2.  **Create PKI Bootstrap Script:** Adapt `test/certs/generate.sh` and SoftHSM setup logic into a single script designed to run non-interactively within an `Init Container`.
  3.  **Develop Init Container:** Create a `Dockerfile` for an Init Container that includes `SoftHSMv2` and the bootstrap script.
  4.  **Create Kubernetes Secrets:** Generate Kubernetes `Secret` manifests for all sensitive values (e.g., database passwords, API keys).
  5.  **Configure Deployments:** Update the application `Deployment` manifests to:
      - Include the PKI `Init Container`.
      - Mount the secrets as environment variables or files.
  6.  **Implement mTLS:**
      - Define a `cert-manager` `Issuer` or `ClusterIssuer` to sign certificates for internal services.
      - Create `Certificate` resources for each service requiring mTLS.
      - Configure services to use these certificates for secure communication.
  7.  **Verification:** Confirm that all pods initialize successfully and that pod-to-pod traffic is encrypted.
- **Deliverables:**
  - `pki-init-container/`: Directory containing the `Dockerfile` and bootstrap script.
  - `secrets.yaml`: Manifest containing all necessary Kubernetes `Secret` resources.
  - `mtls.yaml`: Manifests for the `cert-manager` `Issuer` and `Certificate` resources.

### **Phase 5: Dev Inner-Loop**

- **Goal:** Replace the `docker-compose up` workflow with a fast, automated inner-loop for Kubernetes development using Skaffold or Tilt.
- **Status:** Not Started
- **Inputs:**
  - All Kubernetes manifests generated in previous phases.
  - `Dockerfile` for each service.
- **Tasks:**
  1.  **Tool Selection:** Choose between `Skaffold` and `Tilt` based on project needs.
  2.  **Create Configuration:** Author a `skaffold.yaml` or `Tiltfile`.
  3.  **Define Build Artifacts:** For each service, define how its container image should be built.
  4.  **Define Deploy Strategy:** Configure the tool to deploy all the Kubernetes manifests (Deployments, Services, Secrets, CRs, etc.).
  5.  **Configure File Sync:** Set up file-watching rules to sync code changes into running containers and trigger automatic rebuilds and redeploys where necessary.
  6.  **Validate Workflow:** Run `skaffold dev` or `tilt up`. Verify the application deploys correctly. Make a test code change and confirm automatic redeployment.
- **Deliverables:**
  - A `skaffold.yaml` or `Tiltfile` that fully manages the local development lifecycle.

### **Phase 6: CI/CD Pipeline**

- **Goal:** Automate the building, testing, and deployment of the application to a Kubernetes environment.
- **Status:** Not Started
- **Inputs:**
  - `.github/workflows/boulder-ci.yml`
  - All application source code and Kubernetes manifests.
- **Tasks:**
  1.  **Package Application:** Structure all Kubernetes manifests into a version-controlled Helm chart or a Kustomize base.
  2.  **Setup Container Registry:** Configure a container registry to store production-ready images.
  3.  **Create CI/CD Workflow:** Author a new GitHub Actions workflow (e.g., `k8s-deploy.yml`) that:
      - On every push to the main branch, builds all service images.
      - Tags images with the Git SHA and pushes them to the container registry.
      - Runs all integration tests against a dedicated test cluster.
      - On a new Git tag, packages and pushes the Helm chart (or Kustomize bundle) to a registry.
      - Triggers a deployment to a staging environment for final verification.
  4.  **Validate Pipeline:** Trigger the pipeline and ensure all steps execute successfully, including the integration tests running in-cluster.
- **Deliverables:**
  - A complete `helm-chart/` or `kustomize-base/` directory.
  - The new GitHub Actions workflow file for Kubernetes CI/CD.

### **Phase 7: Observability**

- **Goal:** Integrate a complete observability stack for metrics, logging, and tracing.
- **Status:** Not Started
- **Inputs:**
  - `test/grafana/boulderdash.json`
- **Tasks:**
  1.  **Deploy Monitoring Stack:** Install the `kube-prometheus-stack` Helm chart, which includes Prometheus and Grafana.
  2.  **Enable Metrics Scraping:** Annotate all application `Service` manifests so Prometheus automatically discovers and scrapes their metrics endpoints.
  3.  **Import Dashboard:** Import the dashboard from `test/grafana/boulderdash.json` into Grafana and update data sources to point to the new Prometheus instance.
  4.  **Deploy Tracing Stack:** Install Jaeger or another OpenTelemetry-compatible tracing backend.
  5.  **Instrument Application:** Add OpenTelemetry libraries to the Go microservices to generate and export traces to the tracing backend.
  6.  **Verify Integration:** Check Grafana for application, database, and cache metrics. Check Jaeger for distributed traces flowing through the services.
- **Deliverables:**
  - Helm values for `kube-prometheus-stack`.
  - The updated Grafana dashboard JSON.
  - Pull requests with OpenTelemetry instrumentation added to the services.

### **Phase 8: Hardening & Policies**

- **Goal:** Secure the cluster environment and improve application resilience by implementing security best practices.
- **Status:** Not Started
- **Inputs:**
  - All `Deployment` and `Service` manifests.
- **Tasks:**
  1.  **Implement Health Probes:** Add `livenessProbe`, `readinessProbe`, and `startupProbe` sections to every `Deployment` manifest.
  2.  **Define Network Policies:** Create `NetworkPolicy` resources that enforce a "deny-by-default" stance, only allowing necessary ingress and egress traffic for each service.
  3.  **Implement RBAC:**
      - Create a unique Kubernetes `ServiceAccount` for each microservice.
      - Define fine-grained `Roles` and `RoleBindings` that grant only the permissions required by each service.
      - Update `Deployments` to use these specific service accounts.
  4.  **Review Security Contexts:** Remove any unnecessary `privileged` or `runAsUser: 0` settings from pod security contexts.
  5.  **Validate Policies:** Verify that probes are healthy and that network policies correctly block unauthorized traffic while allowing legitimate requests.
- **Deliverables:**
  - Updated `Deployment` manifests with probes and `serviceAccountName`.
  - A set of `NetworkPolicy` manifests.
  - A set of RBAC manifests (`ServiceAccount`, `Role`, `RoleBinding`).

### **Phase 9: Testing & Rollout**

- **Goal:** Ensure the application is production-ready through rigorous testing and execute a safe, staged rollout.
- **Status:** Not Started
- **Inputs:**
  - All production-hardened Kubernetes manifests.
- **Tasks:**
  1.  **Configure Autoscaling:** Create `HorizontalPodAutoscaler` (HPA) manifests for stateless services to enable automatic scaling based on load.
  2.  **Define Disruption Budgets:** Create `PodDisruptionBudget` (PDB) manifests for critical components to prevent downtime during voluntary cluster maintenance.
  3.  **Author Runbook:** Write a comprehensive `RUNBOOK.md` detailing procedures for deployment, promotion between environments, rollback, and disaster recovery (including database/cache backup and restore steps).
  4.  **Conduct Chaos Drills:** Intentionally inject failures into the staging environment (e.g., delete pods, disrupt network connectivity) to validate the system's resilience and the documented recovery procedures.
  5.  **Execute Production Rollout:** Perform the cut-over to the production Kubernetes environment using a staged strategy (e.g., canary or blue-green).
  6.  **Post-Rollout Monitoring:** Closely monitor application health, metrics, and logs after the final cut-over.
- **Deliverables:**
  - `hpa.yaml` and `pdb.yaml` manifests.
  - `RUNBOOK.md`.
  - A proven and tested rollback plan.
