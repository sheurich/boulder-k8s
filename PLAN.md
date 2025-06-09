# Boulder CA on Kubernetes Planning Document

## **Overview**

Let’s Encrypt’s **Boulder** is a highly modular ACME-based Certificate Authority (CA) system that we aim to deploy on Kubernetes. This design document outlines a production-grade deployment architecture using modern tools and best practices (circa 2025), including **Tilt** for local dev, **Colima** for container runtime on macOS, **Docker Buildx** for multi-arch builds, **Kubernetes** (with **Calico** CNI), **Helm** + **Kustomize** for manifests, **Google Cloud Build** for CI, and **Artifact Registry** for images. Crucially, the design emphasizes **WebTrust** and **CA/Browser Forum** compliance: encrypted databases, HSM-based private key management, comprehensive audit logging, and strict network security controls.

We will leverage Boulder’s reference configuration (from its Docker Compose setup) and apply hardening for a real-world CA deployment. The outcome is a blueprint for dev (local), staging (GCP), and prod (bare-metal) environments, each with appropriate security, scalability, and compliance measures.

## **Architecture & Components**

Boulder’s architecture is split into multiple components (microservices), each with a specific role in the certificate lifecycle. These components communicate via gRPC with mutual TLS, and are designed to be isolated by security context. The major Boulder services include:

- **ACME API (Web Front End)** – Handles ACME client requests (account registration, certificate orders). This service (Boulder WFE) is the public-facing API. It requires inbound internet access on ACME ports and is typically behind an HTTPS reverse proxy.
- **Registration Authority (RA)** – Orchestrates the issuance process. It receives requests from the WFE, coordinates domain validation and certificate issuance. The RA does **not** need direct internet access (it talks only to internal services like the VA and CA).
- **Validation Authority (VA)** – Performs domain validation (e.g. HTTP-01, DNS-01 challenges). The VA needs outbound internet connectivity to reach applicant websites or DNS for challenge verification. It listens for instructions from the RA and reports validation results back.
- **Certificate Authority (CA)** – Responsible for signing certificates. The CA only accepts requests from the RA (it doesn’t take public traffic). The CA holds (or accesses) the intermediate CA signing keys, which in production are stored in an HSM.
- **Storage Authority (SA)** – Provides persistent storage interface (backed by a database). All components interact with the SA for reading/writing objects (accounts, orders, certs) which are stored in the MySQL database. The SA abstracts the database access and enforces data integrity.
- **Publisher** – Submits signed certificates (pre-certificates) to Certificate Transparency logs and handles related callbacks. It needs outbound internet access to contact CT log servers.
- **OCSP Responder** – Serves OCSP responses to clients (browsers). This service is public-facing (clients on the internet query it) and responds on OCSP HTTP ports. Boulder pre-computes OCSP responses and stores them (e.g. in the DB); the responder fetches signed OCSP records from storage.
- **OCSP Updater / CRL Updater** – Internal processes that monitor certificate status and generate revocation data. For example, the OCSP updater instructs the CA to sign OCSP responses for new or revoked certs, which are then stored until they expire. A CRL generator may also run for backup status information.
- **Nonce Server** – Provides cryptographic nonces for ACME transactions across distributed systems. (In Boulder’s distributed design, separate nonce services in different zones prevent replay attacks. For our deployment, a single nonce service per cluster or per region is sufficient.)
- **Auxiliary Services** – e.g. **Database (MySQL)**, **Redis caches**, and **Consul**. Boulder uses MySQL (MariaDB) as its primary data store, and Redis for caching (e.g. caching OCSP responses or rate-limit counters). The Docker Compose reference runs multiple Redis instances with specific configs (OCSP and Nonce/RateLimit). Consul is used in Boulder’s dev environment for DNS service discovery, though in Kubernetes we can use native DNS or a lightweight alternative.

**Inter-Service Communication:** Boulder components talk over gRPC with mutual TLS. Each service has a certificate issued by an internal CA (distinct from the public CA) and a configuration of allowed client SANs. In our design, we will generate a Kubernetes **Secret** containing this internal PKI (a root CA and a certificate/key pair for each Boulder service). This ensures that only authorized Boulder microservices can connect to each other, enforcing the security contexts defined by Boulder’s model. (Using the in-repo test certificates is insecure and not acceptable.)

**Network Segmentation:** Following CA/B Forum Network Security Requirements, we isolate components by their required network access. Only the **WFE**, **OCSP Responder**, and (optionally) the ACME HTTP challenge port on the VA need to be reachable from the internet. The **Publisher** and **VA** need outbound internet access for CT and validation traffic. **RA**, **CA**, **SA**, and databases should be on an internal network segment with no direct internet access. This segmentation aligns with best practices: _“CA infrastructure MUST be segmented into separate networks…”_. In Kubernetes, we achieve this via **NetworkPolicies** (and possibly separate node pools or subnets for different roles). We will define policies so that:

- Public ingress is allowed only to WFE and OCSP pods (on necessary ports).
- WFE can communicate with RA (and SA as needed) internally, but external parties cannot directly reach RA/CA.
- RA can only talk to WFE, VA, CA, SA – and cannot initiate arbitrary outbound connections.
- CA only accepts connections from RA (and maybe from OCSP updater service).
- VA and Publisher can initiate outbound connections (to validation targets and CT logs, respectively), but their inbound access is limited to RA/SA.
- All other traffic is denied by default.

Kubernetes **Calico** is used as the CNI to enforce these NetworkPolicies (Calico supports a robust implementation of network policy including egress control). This network model ensures a compromise in a DMZ component (e.g., WFE) cannot directly reach the signing CA service, fulfilling the WebTrust principle of layered network security.

## **Security and Compliance Requirements**

Deploying a public CA requires strict adherence to **WebTrust for CAs** and **CA/Browser Forum Baseline Requirements (BRs)** and Network Security Requirements (NSRs). Our design addresses these as first-class considerations:

- **Hardware Security Module (HSM) for Private Keys:** All long-term CA private keys (the intermediate signing keys and OCSP responder keys) are stored and used **in an HSM**. We integrate Thales **Luna HSMs** (FIPS 140-2 Level 3 validated) for key management, as ISRG (Let’s Encrypt) does. The Boulder CA service will use the HSM via PKCS#11. In development and non-production environments, we use SoftHSM (a software HSM) as a drop-in replacement to simulate HSM access. **Key Usage:** The HSM holds the active intermediate certificate’s key (RSA and ECDSA; at least one of each per Boulder’s requirement) and the OCSP signer certificate’s key. Boulder will be configured to use these keys via PKCS#11 sessions – meaning the actual private key material never leaves the HSM device. This satisfies WebTrust requirements for secure key protection. We will mount the vendor’s PKCS#11 library in the CA pod and pass needed connection info (e.g., partition address/credentials) as Kubernetes Secrets. For example, Thales Luna NetHSM uses a client config and certificate for connectivity; these will be provisioned on the cluster nodes or provided to the container securely. The **HSM integration** replaces Boulder’s default SoftHSM config with production settings – this is done by supplying Boulder’s JSON configs with the correct `pkcs11` module path and key identifiers.
- **Database Encryption:** The Boulder MySQL/MariaDB database will be encrypted to protect sensitive data at rest. This includes enabling InnoDB tablespace encryption and/or disk-level encryption on the persistent volumes. On GCP, we can use CMEK (Customer Managed Encryption Keys) for disks, and on bare-metal we will use LUKS or self-encrypting drives. Additionally, database backups will be encrypted. While Boulder doesn’t store subscriber private keys (ACME protocol has clients generate keys), it does store ACME account details, pending challenges, and audit logs, which must be safeguarded. We will also enforce TLS for any connection to the database (within Kubernetes this means using cluster-internal connections, but if any external DB admin access is needed, it will require TLS and strong auth).
- **Audit Trails & Logging:** Boulder flags security-critical events with “[AUDIT]” in log messages. Our deployment will capture these events and store them in an **immutable audit log** system. For example, we will aggregate logs to a central logging service (like Elasticsearch or Cloud Logging) and apply log retention and integrity controls (e.g., write-once storage for audit logs). All Baseline Requirements auditable events (certificate issuance, revocation, login attempts, etc.) will be retained per compliance (at least 7-10 years as required). We will establish a logging policy to ensure **audit logs are reviewed** and any anomalies trigger alerts (integrating with SIEM). Boulder’s built-in audit logging is leveraged by filtering log streams for “[AUDIT]” entries and sending those to a dedicated index or pipeline. Additionally, Kubernetes cluster audit logs (for API actions) and OS logs will be considered part of the compliance footprint.
- **Network Security & Least Privilege:** As discussed, the network architecture follows CA/B Forum NSRs for segmentation. In Kubernetes terms, we not only isolate via NetworkPolicy, but also use Kubernetes **Role-Based Access Control (RBAC)** to ensure only authorized processes can perform certain actions. For instance, the Boulder pods will run with minimal privileges: no hostNetwork (except perhaps for an ingress controller), no access to host IPC or devices (except HSM device via library), and with read-only root filesystems where possible. We adopt Kubernetes Pod Security Standards (“restricted” profiles) to prevent privilege escalation. Secrets (like HSM PINs, DB passwords) are not stored in code or images, but in Kubernetes Secrets, and mounted as read-only volumes or exposed via env vars only to the pods that need them.
- **WebTrust Operational Controls:** In addition to technical controls, we plan for multi-operator control for critical operations. For example, HSM key activation might require quorum authentication (which is handled outside Kubernetes by the HSM). We’ll document procedures for quarterly key backups, dual-control for HSM administration, separation of duties (operators of the Kubernetes cluster will not have direct access to HSM keys, etc.). While these procedural details are outside the scope of deployment manifest, our design supports them (for instance, we can require human intervention to load HSM credentials into the cluster). We will integrate **secure secrets management** – e.g., using HashiCorp Vault or Cloud KMS for secrets could be an extension, but at minimum, Kubernetes secrets are encrypted at rest (in etcd) and restricted via RBAC.
- **Compliance Audits:** To facilitate external audits (WebTrust), the deployment will maintain documentation and evidence for all the above controls. We will include references to a **Security & Compliance playbook**, mapping each requirement (database encryption, key protection, logging, network controls) to where it is implemented in our Kubernetes setup. This ensures that an auditor can trace requirements to concrete configurations or processes.

## **Kubernetes Deployment Architecture**

### **Containerization and Build Pipeline**

We will containerize Boulder’s services using a unified approach. Boulder is written in Go and its source includes a monolithic binary with subcommands for each service (e.g., `boulder-ca`, `boulder-ra`, etc.). We will build a **single multi-service container image** for Boulder – this image will contain the Boulder binary and any necessary dependencies (like the PKCS#11 library stubs for HSM, MySQL client, etc.). Using one image for all services simplifies the build and ensures consistency (all services run the same version of code). Different Kubernetes Deployments will use the same image but start the binary with different subcommands and configs.

We use **Go Modules** to manage Boulder’s dependencies and ensure reproducible builds. Our CI/CD pipeline uses **Google Cloud Build** to compile and package the Boulder image. We will target multiple architectures: primarily `linux/amd64` for production (and staging) and `linux/arm64` for developers using Apple Silicon laptops or ARM-based servers. Docker Buildx is configured in Cloud Build to produce a multi-arch manifest and push to **Artifact Registry**.

**Docker Build**: The Dockerfile will start from a minimal base (e.g., `distroless` or Alpine for a small attack surface) and copy the Boulder binary and configs. It will also include the SoftHSM library for dev/test and allow mounting a vendor HSM client in prod. We will enable compiler hardening flags (like PIE, static linking where possible, etc.) for security.

**Multi-Arch Build Example:** Using Cloud Build with Buildx, we create a builder and push multi-arch images. Below is a snippet of the Cloud Build config (`cloudbuild.yaml`) for the Boulder image:

_(The first step registers QEMU for cross-building; the second does a multi-arch build and pushes the image. The <code>$SHORT_SHA</code> tag (or a version) is used, and the image is stored in Artifact Registry.)_

In addition to the Boulder app image, we will use off-the-shelf images for dependencies: MariaDB (with a hardened config), Redis, and possibly Vault (if we use it for secrets). These will be pulled from trusted repositories and tagged at specific versions (e.g., MariaDB 10.5 or later, with any 2025 updates).

### **Helm Chart and Configuration Management**

We will create a **Helm chart** named `boulder` to package all Kubernetes manifests needed. Helm allows templating for different environments (dev, staging, prod) via values files. To further enforce best practices, we may layer **Kustomize** on top for site-specific overlays (especially for prod hardening that might not be default in the chart). Each Boulder component (WFE, RA, VA, etc.) will be a separate Deployment (or possibly StatefulSet for those needing stable identity), defined in the Helm templates. The chart will also include Services for internal communication and any ConfigMaps/Secrets for configuration.

**Manifests Hardening:** The Kubernetes manifests will be written with security context in mind:

- All pods run as a non-root user (we’ll use a dedicated UID/GID in the Docker image for Boulder).
- File systems are read-only except for specific mount points (like /var/lib/softhsm for dev, or emptyDir for any runtime state).
- Capabilities dropped (Boulder doesn’t need any Linux capabilities).
- Liveness and readiness probes will be configured to use Boulder’s health endpoints (each component has a debug port with health checks – we will secure these or restrict them to localhost).
- Resource requests/limits set for each pod based on expected load (e.g., CA pods might need more CPU for cryptographic operations, VA pods more network, etc.).

**Helm Values:** We’ll use values files to toggle features per environment. For example, in dev and staging we use SoftHSM; in prod we use the real HSM. We also adjust the number of replicas (e.g., dev may run 1 of each, prod 2+ for HA). Below is a snippet of a **Helm values.yaml** illustrating some critical configurations:

_In the production values above, we enable HSM integration by specifying the library and referencing a K8s Secret for the PIN. In dev, HSM is disabled and Boulder will default to using SoftHSM (which we simulate via an image or the Boulder container itself in SoftHSM mode)._

These values feed into ConfigMap templates that render Boulder’s JSON configuration files. For example, the Helm chart will template the CA service’s config (ca.json) to include either a SoftHSM module path or the Luna HSM module path depending on `hsm.enabled`. The **Secrets** like `hsm-pin-prod` and `db-password-prod` will be created (populated out-of-band) and mounted as environment variables or files for the pods.

**Service Discovery:** In Kubernetes, we don’t need Consul for service discovery (as used in Boulder’s Docker Compose). Instead, we will use internal DNS. Each Boulder service will be given a DNS name (Service) like `boulder-ca.prod.svc.cluster.local`. We will configure Boulder’s internal gRPC client addresses to those names. We must ensure the internal mTLS certificates include these DNS names in their SANs (or we set the `host_override` in Boulder config to match the service DNS). For instance, RA’s config might point to `ca.boulder` as the CA endpoint – we will either use Kubernetes **Service aliases** or configure CoreDNS with stub domains such that `*.boulder` resolves to our service ClusterIPs. Simpler: we can set the Boulder configs’ `serverAddress` fields to the full Kubernetes DNS names and generate internal certs for those names. This removes the need for Consul entirely in our k8s deployment.

### **Network Policies and Zoning**

We implement Kubernetes **NetworkPolicy** objects to enforce the traffic rules between pods and to/from the cluster. By default, all pods in the Boulder namespace will be isolated (default deny). Then we allow specific flows:

- **Ingress to WFE/OCSP:** Only allow from the public ingress (if we use an Ingress controller) or generally open to the internet via a LoadBalancer. We’ll use an Ingress resource with TLS termination at an Nginx (or HAProxy) ingress controller for the ACME API (WFE) and a Service of type LoadBalancer or NodePort for OCSP if needed. The WFE pods themselves only accept traffic on the cluster network from the ingress controller (to enforce that, we might put WFE in a DMZ namespace or use an admission controller – but given the complexity, we assume the ingress controller is the entry point).
- **WFE -> RA/Nonce:** Allow the WFE pods to call the RA service (ACME requests flow WFE -> RA) and to fetch nonces if needed. Also WFE to SA if WFE directly uses storage (in Boulder’s design WFE mostly goes via RA).
- **RA -> CA:** Allow RA to initiate connections to CA (for certificate signing).
- **RA -> VA:** Allow RA to instruct VA for validation.
- **VA -> External:** Permit VA pods to access **80/443** outbound (for HTTP/DNS validations and CAA checks). By default, other pods won’t have egress except maybe Publisher and OCSP (OCSP updater might fetch CRLs externally in some configs).
- **CA -> (RA or DB)**: The CA might need to call back RA for SCT (in Boulder, CA calls an RA “SCTProvider” service). We’ll allow CA -> RA on that specific port. CA also needs to reach the database or SA for storing issued certs and OCSP records. If CA talks only via SA service, we restrict CA to SA.
- **Publisher -> External:** Allow Publisher to reach CT log endpoints (HTTPS).
- **Internal DB/Cache:** Only SA (and maybe CA/RA) can talk to MySQL; only relevant Boulder components can talk to Redis caches. We lock down those ports from general access.

Below is an **example NetworkPolicy** (YAML) to illustrate some of these rules in Kubernetes:

_Explanation:_ The first policy allows only WFE pods to connect to RA pods on the RA service port. The second allows RA to connect to CA. The third allows RA to VA. A default-deny policy at the bottom ensures no other traffic is allowed (any policy not explicitly whitelisted is blocked). We would similarly define policies for Publisher (allow from CA to Publisher if needed, and allow Publisher’s egress to CT log hosts via an Egress policy on port 443), and for database access (e.g., allow SA or Boulder pods to connect to MySQL on port 3306, but nothing else).

Additionally, Calico **GlobalNetworkPolicy** could be used to enforce cluster-wide rules (for example, “only ingress from these IPs to the cluster ingress controller”), but those details are environment-specific (e.g., managed at the cloud firewall level in GCP and by network firewalls on prem).

### **Secrets Management**

**Kubernetes Secrets** will store sensitive material:

- **HSM Credentials:** Thales Luna HSMs usually require a client certificate, key, and a partition password (PIN). We will load the client cert/key into the container as files (possibly via a secret volume) and the PIN as an environment variable. The secret `hsm-pin-prod` (referenced in Helm values) contains the PIN, restricted to the CA pods. The HSM client certificate could also be in a secret if needed and mounted in the container’s expected location (e.g., `/etc/luna/`).
- **Database Password:** Stored in a secret and only attached to the MySQL StatefulSet and Boulder SA (or any component that needs direct DB access).
- **Internal TLS Keys:** The internal PKI CA and per-service certificates for gRPC encryption can be stored either in a secret per service or one secret with all keys (encrypted at rest). To simplify, we might generate these certs in advance and bundle them in one Kubernetes secret `boulder-grpc-certs` which contains a key/cert for each component (with distinct CNs). Only Boulder pods mount this secret.
- **ACME account signing keys (if any)**: Boulder doesn't manage ACME client keys (the clients do), so no need to store those.
- **API keys or external credentials:** If Boulder’s config includes any external API keys (for example, if an external email service or SafeBrowsing API was used), those too would go in secrets.

We will use Kubernetes RBAC to ensure only the Boulder namespace and appropriate service accounts can read these secrets. In GKE or others, enabling secret encryption with a KMS key is recommended for extra security.

Optionally, we could integrate **HashiCorp Vault** for secrets: pods would retrieve secrets at startup via Vault agent, rather than storing in etcd. This can be a later enhancement. For now, standard K8s Secrets (encrypted by etcd and limited in scope) suffice.

### **Pod Security and Hardening**

Each Boulder pod runs with a minimal security context:

- **PodSecurityPolicy (PSP)** or the newer Pod Security admission (set to `restricted`) is in place for the namespace. This ensures no privileged pods or host mounts are allowed. The Boulder deployments will include a `securityContext` specifying `runAsNonRoot: true` and a specific `runAsUser` UID. We also set `allowPrivilegeEscalation: false` in all containers.
- **Filesystem**: The Boulder container image is built to run as non-root, and the container’s filesystem is mostly read-only. We mount a scratch **EmptyDir** for any needed writable paths (Boulder might need to write transient data or store caches – e.g., softHSM token directory in dev – we mount those paths explicitly). Config files are mounted read-only from ConfigMap/Secret.
- **Capabilities**: The container does not need any special Linux capabilities, so we drop all (`capDrop: ["ALL"]`).
- **Seccomp/AppArmor**: If available, we apply a seccomp profile (e.g., Docker default or a custom profile restricting syscalls). We also use AppArmor (on compatible nodes) to restrict the process (e.g., disallow executing any binaries not in the image, etc.). This further reduces the risk from a compromised service.

**In Kubernetes terms, we could exemplify this with a fragment of the Boulder deployment YAML:**

Each component’s Deployment will look similar, just with different args and config. The **PodSecurity** admission set to restricted ensures any misconfigurations that would create a privilege escalation are blocked.

### **Ingress and Service Exposure**

For the ACME API (WFE), we will use an **Ingress** resource (with an NGINX ingress controller or similar) to handle TLS termination. Boulder’s WFE can technically serve ACME over plaintext HTTP (because Boulder expects to be behind TLS offload – in Let’s Encrypt, a CDN terminates TLS). We will follow that model: the Ingress will have the public CA’s certificate (which could be from Let’s Encrypt itself or another CA if this is a new CA service), terminating TLS on port 443 and forwarding requests to Boulder WFE on port 4001 (the internal ACME port used in Boulder config). We will ensure the WFE is configured to _not_ serve TLS itself but to trust that it’s behind an HTTPS proxy (alternatively, Boulder WFE has a `--tls-addr` option which we can ignore if using an external terminator). The ingress controller can also enforce rate limits or IP allow-listing if needed.

For the **OCSP Responder**, we have a couple of choices:

- Since OCSP responses are lightweight and frequent, we might also put them behind the same ingress or a LoadBalancer. However, OCSP is usually served over HTTP (not HTTPS) for broad compatibility. We can still terminate TLS if we want to secure transport (not typical for OCSP). Likely, we will expose OCSP via a LoadBalancer service on port 80, or use the ingress controller in “passthrough” mode (no TLS) with a dedicated DNS (e.g., ocsp.example.com).
- We will set the OCSP responder’s Service with an externalTrafficPolicy (Cluster vs Local) depending on if we want source IP preservation (not critical for OCSP). A small NodePort can be used if needed.

Everything else (RA, CA, etc.) has no ingress from outside. They are only cluster-internal. For connectivity between on-prem prod and perhaps other systems (like an external monitoring system), we might open specific ports via a bastion, but that’s outside Boulder’s scope.

## **Local Development Environment (Tilt & Colima)**

For developers, we want an easy way to spin up Boulder and all dependencies on a local machine. **Tilt** will be used to orchestrate this. Developers can run `tilt up` to build images and deploy to a local k8s (for example, a **Kind** cluster running in Colima). The Tilt configuration will leverage our Helm chart with a dev values file, or use Kustomize overlays, to deploy a lightweight instance of Boulder.

**Colima** provides a container runtime on macOS (with Lima VM under the hood) which can run KinD or Minikube clusters efficiently. We assume the developer has Colima and KinD installed. The **Tiltfile** will then:

- Start (or connect to) a local Kubernetes cluster (Tilt can work with the current kubecontext, so the developer would ensure their Colima/Kind cluster is the current context).
- Build the Boulder image using the local Docker daemon (or Buildx if on ARM Mac to get an ARM image). We can configure Tilt to do a live Docker build or use its Fast Build features for quicker code-sync.
- Apply the Kubernetes manifests (possibly via Helm template). Tilt supports a `helm` function or we can call `kubectl apply` on a rendered manifest.

We also incorporate live reload: if a developer changes the Go code, Tilt will rebuild the binary and update the container.

**Example Tiltfile:**

Using the above, a developer can run ACME clients against `localhost:4001` to test issuance (the Tilt port-forward connects to WFE). We run SoftHSM in this environment so the developer doesn’t need an actual HSM. The dev deployment might also disable certain heavy components (for example, the Publisher could be stubbed out or pointed to a dummy CT log server container like Boulder’s `ct-test-srv`).

We include lightweight images for dependencies: we might use a small MySQL 8 or MariaDB 10 container with an EmptyDir (data not persisted), and a single Redis instance (instead of four). The dev config (as shown in `dev-values.yaml`) uses a root DB user with no password for simplicity and might disable database encryption.

**Tilt Security for Dev:** Even in dev, we encourage running the services as non-root, and not exposing unnecessary ports. However, dev mode is naturally less strict. We do ensure that the dev environment still uses TLS for gRPC between components (Tilt can generate or use the test certificates in Boulder). This way, dev and prod configs don’t diverge drastically in mechanism (only in credentials).

## **CI/CD Pipeline (Google Cloud Build & Artifact Registry)**

Our CI/CD pipeline will automate building, testing, and releasing the Boulder deployment.

- **Continuous Integration (CI):** On each commit to the repository (or each merge to main), Cloud Build triggers will run. Key steps include:
  - **Go Unit Tests** – run `go test ./...` on Boulder’s code (and any custom patches we maintain) inside a build step (using a Go builder image or Dockerfile stage). Ensuring Boulder’s own tests pass gives confidence in the build.
  - **Docker Build & Push** – as shown earlier, build multi-arch images using Buildx. Tag the image with the Git commit and perhaps a semantic version if applicable.
  - **Helm Chart Lint** – run `helm lint` on the chart to catch any chart issues.
  - **Deployment Dry-Run** – optional: use `helm template` with prod values and run `kubectl apply --dry-run`against a test cluster to ensure no validation errors in manifests.
  - **Push Helm Chart** – if we maintain a Helm repo (e.g., an Artifact Registry for Helm or GitHub Pages), package the chart and push it so it can be referenced in deployments.
- **Continuous Delivery (CD):** We outline promotions from one environment to the next:
  - For the **staging environment**, we can have Cloud Build (or Google Cloud Deploy) auto-deploy the new image and config after CI passes. This might be a separate pipeline triggered on tagging a release. It could, for example, use `kubectl` or Helm to upgrade the staging cluster (which lives on GCP). This gives us a staging Boulder instance for further integration tests.
  - Production deployment might not be fully automated (due to the sensitive nature, we likely require a manual approval step). However, we will provide infrastructure-as-code (Helm values for prod) so that a deployment is a deterministic, version-controlled operation. We can use GitOps (e.g., Argo CD or Flux) for prod cluster – where a human reviews and then the GitOps controller applies the new manifests.

**Google Cloud Build** will also handle multi-arch nicely by either QEMU emulation or using separate build nodes. We showed a Cloud Build snippet earlier; that job will output an image accessible to both ARM64 and AMD64 nodes. This ensures that the same image can run on developer machines (ARM Mac with Colima) and on prod servers (x64).

We store the Docker image in **Artifact Registry** which is private to our project for security. Access to pull the image in prod will be restricted to the cluster’s node IAM or via pre-loaded credentials.

Additionally, we integrate **automated scans**: Artifact Registry can do vulnerability scanning on images. We enable that to catch any known CVEs in the Boulder image or base layers. Cloud Build can be configured to fail if critical vulnerabilities are found (or at least notify).

**CI Example Snippet:** The key part (multi-arch build) was shown earlier. Another useful snippet is a Cloud Build step for running tests:

And a step to push Helm chart:

(where `helm cm-push` might push to an Artifact Registry Helm repo; alternatively use `gsutil` or Git to upload chart package).

**Continuous Monitoring of Boulder Releases:** Since Boulder doesn’t have formal versioned releases and is updated frequently, our pipeline will track the upstream Boulder repository. We plan a job that periodically pulls Boulder’s upstream main or tags, and runs integration tests to ensure our deployment still works. This way we can regularly merge upstream changes and trigger a new build, so we stay up-to-date and secure.

## **Deployment Environments**

We have three primary environments: **Dev (local)**, **Staging (GCP)**, and **Production (Bare-metal)**. The Helm chart and configs are designed to be portable across these, with differences captured in values or overlays.

### **Development (Local Kubernetes)**

Developers use Tilt/Colima as described to run a full Boulder stack locally. This environment uses minimal resources: one instance of each Boulder component, SoftHSM for keys, and no CT logging (or a fake CT server). NetworkPolicies can be relaxed here (or even turned off) to simplify development, but our Helm chart will by default include them – developers can disable via values if needed.

The dev environment is not meant for compliance testing, but it is configured to be functionally as close to prod as possible. For example, we use the same Boulder JSON config structure, just pointing to SoftHSM. This catches issues early (e.g., misconfigured PKCS#11 module) in a safe setting.

### **Staging (GCP)**

Staging will be a deployment in a secure project on GCP, possibly on **GKE** or on GCE VMs with a Kubernetes cluster (if more control is needed). We choose GKE for ease of maintenance, but ensure to use a private GKE cluster (no public endpoint for master, and controlled network). The staging environment’s purpose is to mirror production in functionality and allow external clients to test against it (if this CA offers a public test service, similar to Let’s Encrypt’s staging).

**Staging specifics:**

- We use the same Helm chart with a `staging-values.yaml`. Possibly very similar to prod except:
  - HSM: We might not have a physical Thales HSM in staging. Options are: use a Cloud HSM (e.g., AWS CloudHSM or GCP Cloud KMS) or use SoftHSM here as well. Using SoftHSM in staging is acceptable if we treat staging as non-trusted (issuing test certs only). If we want a higher fidelity, we could connect staging to a network HSM partition (Thales can partition HSMs for dev/test). Let’s assume for now that SoftHSM is used in staging for convenience, but with the same key sizes and algorithms as prod.
  - Database: Could use Cloud SQL managed MySQL for reliability, or run a MySQL in the cluster with a Persistent Disk. Since staging should mimic prod, we may set up a MySQL with disk encryption and daily backups (GKE can schedule snapshots).
  - Scale: Staging might run fewer replicas (maybe 1 of each service) to save cost, but we ensure at least one of each type (RSA and ECDSA CA if applicable) to test both issuance paths.
  - Ingress: Use a staging domain (e.g., acme-staging.example.com) and a non-publicly trusted TLS cert (or a self-signed one that clients trust for testing). Alternatively, we can use Let’s Encrypt’s own cert for our staging API since it’s just for testing – but that might be ironic; more likely we’d use an internally trusted cert.

We will deploy staging on GCP VMs (with GKE) that are **amd64** to match prod as much as possible. However, if we have any ARM nodes (GKE Autopilot might schedule on ARM), our multi-arch image covers that.

Monitoring and logging in staging: we integrate with **Google Cloud’s operations suite** (formerly Stackdriver). Staging cluster sends logs to Cloud Logging; we set up metrics collection (GKE has monitoring). This helps us test our monitoring before prod.

### **Production (Bare-Metal AMD64)**

Production deployment will be on a Kubernetes cluster running on bare-metal servers (amd64) in one or multiple data centers. We assume a high-security environment: locked-down facilities, HSMs physically present, etc. The Kubernetes cluster will be dedicated to the CA systems to minimize multi-tenant risks. Likely, multiple master nodes for HA, etc., and etcd encryption turned on.

**Key elements for prod:**

- **HSM Integration:** The Thales Luna network HSMs are set up and accessible to the cluster via a secure network link. We install the Luna client software on each node (this could be baked into the node OS or provided as a daemonset). The Boulder CA pods will have access to the HSM client libraries and configuration. We might run an init-container in the CA Deployment that tests HSM connectivity (to fail fast if HSM is unreachable). The HSM usage will require FIPS mode; we ensure the cluster nodes are running a FIPS-enabled OS kernel if required (to satisfy any FIPS compliance at the OS level too).
- **Node segregation:** If possible, we separate nodes by role. For example, HSM client software is only installed on nodes that schedule CA pods (and maybe OCSP signer if separate). We can label these nodes `role=ca` and use nodeSelectors or taints/tolerations to ensure only CA and maybe RA pods run there. WFE/VA (DMZ components) could run on separate nodes that have egress to internet but no route to internal networks except what’s needed. This physical separation complements NetworkPolicies at the cluster level. It mirrors the idea of multi-tier segmentation (DMZ vs internal network) on Kubernetes.
- **Scalability:** Boulder can scale horizontally for many components. In production, we may run multiple WFE pods behind the ingress, multiple RA pods (Boulder is stateless in RA layer, using the DB), and multiple CA pods (since Boulder allows parallel CAs sharing HSM keys or each handling a subset of keys). We ensure the DB is robust – likely a primary-replica MySQL setup. If we choose to run the DB outside the cluster (on actual DB servers or a managed DB), we will secure the connectivity (private VLAN or direct attach). If inside cluster, use a StatefulSet with PV on a SAN, with sync replication to another site if needed (e.g., via Galera cluster).
- **Backup & Restore:** In prod, we configure automated backups for the database (daily dumps or incremental backups). We also backup any PersistentVolumes (though ideally Boulder state is all in the DB). The HSM keys themselves will be backed up via HSM backup tokens/devices per Thales procedures (this is outside Kubernetes – an HSM backup HSM or smart card set is used). We document a Disaster Recovery plan: how to restore Boulder in a new cluster using DB backups and HSM key restore, if the primary site goes down.
- **Compliance checks:** Production environment will be subject to audit, so we enable all audit logging (and ship logs to a secure SIEM outside the cluster as well, to survive if cluster is compromised). We also enable intrusion detection: e.g., running something like Falco on the cluster to detect unusual container behavior (like if a shell is spawned in a Boulder container – which should never happen).

The deployment pattern could also include an **offline root CA** which is not part of Kubernetes. That root signs the intermediates that Boulder (the online CA) uses. Procedures for that (key ceremonies, offline storage) are handled separately, but our design anticipates loading the resulting intermediate certs and keys (the latter into the HSM) and configuring Boulder’s CA service with them.

## **Monitoring, Logging, and Auditing**

A production CA must be closely monitored. We integrate monitoring on multiple layers:

- **Application Metrics:** Boulder exports Prometheus metrics or at least health stats on its debug endpoints. We will deploy a Prometheus instance (or use an existing one) to scrape Boulder metrics. Key metrics include number of successful/failed validations, issuance counts, OCSP response metrics, etc. We will set alerts on abnormal conditions (e.g., a sudden drop to zero new certs might indicate a stuck component; a spike in failed validations might indicate an external DNS outage; high database latency, etc.).
- **Logging:** All Boulder logs (stdout/err from pods) are collected via Fluent Bit/Fluentd to an Elasticsearch cluster or Google Cloud Logging. Audit-tagged events are routed to a dedicated index with long retention. We also capture Kubernetes audit logs (to detect any changes or access in the cluster). The logs will be monitored for security events. For example, multiple failed HSM access attempts or unexpected network connections (we could log blocked network policy hits via Calico if needed).
- **Tracing:** Boulder’s distributed system can benefit from tracing. The Boulder docker-compose included Jaeger for tracing in tests. We can optionally include Jaeger in our deployments (especially in staging) to trace requests across WFE -> RA -> VA -> CA -> Publisher. This is useful for performance tuning and debugging complex issues. In production, we might limit tracing to avoid performance overhead, but have it available when needed (perhaps triggered on certain transactions).
- **External Monitoring:** We will also do black-box monitoring: e.g., run a cron job that uses Certbot (or our ACME client) against the production API periodically to ensure it issues a cert, and alert if it fails. Similarly, monitor the OCSP URL by querying a known certificate’s status to ensure OCSP is serving correctly and within response time SLAs.
- **Alerts:** We configure alerting rules for conditions like:
  - HSM latency or error rates (perhaps via metrics from HSM if available, or from Boulder logs).
  - Database connection issues or replication lag.
  - High error rate in ACME requests (could indicate an outage).
  - Security alerts: e.g., an admin kubeconfig used at odd hours (detect via Kubernetes API server audit logs).
  - Capacity thresholds (disk space, certificate issuance nearing any configured rate limits, etc.).

Finally, **auditing**: We will conduct periodic internal audits of the system configuration against compliance checklists. The design mandates things like password policies (for HSM PIN, DB user), multi-factor auth for console access, etc., which would be verified regularly.

## **Backup and Disaster Recovery**

Backup and DR are critical for a CA to ensure continuity and to avoid catastrophic loss of trust (e.g., losing the only copy of a key). Our strategy includes:

- **Database Backups:** The MySQL database is the heart of Boulder’s state (issued cert records, account data, etc.). We will take nightly full backups and hourly incremental backups. In GCP, if using Cloud SQL, we’d enable automated backups and point-in-time recovery. On bare-metal, we can use Percona XtraBackup or MyDumper to take consistent backups. These backups will be encrypted and stored off-site (e.g., in secure cloud storage or tape). Restoration procedure is documented and tested on staging periodically.
- **HSM Key Backups:** Using Thales Luna tools, we will backup the HSM partition that holds the intermediate and OCSP keys. Typically, Luna provides backup HSM or smartcards. We ensure backups are done after any key generation ceremony and whenever keys are rotated. These are stored securely (e.g., in a safe) and require multi-person access, as per WebTrust.
- **Kubernetes State:** While we can recreate clusters from code (infra-as-code), we also take backups of cluster state (e.g., etcd backup or at least export of all Kubernetes manifests and secrets). At minimum, the Helm chart + values in source control means we can recreate the resources. Secrets (like HSM PIN) we also escrow in a secure vault in case the cluster is lost.
- **Disaster Recovery Site:** Ideally, we maintain a secondary DR site. This could be another bare-metal cluster in a distant location or possibly a cloud-based failover. The DR site would have its own HSM with copies of the keys (activated only during DR). We might run Boulder in hot-standby there, or at least have the ability to bring it up quickly. Database replication can be set up from primary to DR site (with delayed apply to avoid corruption propagation). This design though focuses on single-site; multi-site would just be an extension: either active-active (both issuing under same intermediates, which requires careful coordination and consistent state) or active-passive (manual failover).
- **Recovery Drills:** We will do drills where we simulate loss of the primary cluster and recover on staging or DR environment using the backups. This tests that our backups are valid and our documentation is adequate.

## **Conclusion**

In summary, this design provides a comprehensive plan to run Let’s Encrypt’s Boulder CA in a Kubernetes environment with a strong emphasis on security and compliance. We have mapped Boulder’s complex microservice architecture onto Kubernetes constructs, introducing strict network segmentation and access controls in line with CA/Browser Forum guidelines. By using HSMs for key management and robust auditing/logging, we adhere to WebTrust principles while leveraging modern cloud-native tooling for automation and scalability.

This proposal balances the needs of development (easy iteration with Tilt, testing with SoftHSM) and operations (reliable CI/CD, monitoring, backups) with the paramount need to protect the CA’s crown jewels (private keys and secure operations). With this design, an engineering team can proceed to implementation confident that the CA deployment will be secure, compliant, and maintainable as a production service.
