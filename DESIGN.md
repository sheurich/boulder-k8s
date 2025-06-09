# Boulder on Kubernetes Design Document

## 1. Overview

This document outlines the design for deploying Let's Encrypt's Boulder Certificate Authority (CA) software on a modern Kubernetes platform. The primary goal is to establish a highly secure, compliant, scalable, and automated CA infrastructure that maintains parity between local developer, continuous integration, cloud staging, and bare-metal production environments wherever possible.

The strategy will focus on ensuring _functional and behavioral equivalence_ of the CA service across environments. The staging environment will serve as a high-fidelity platform for testing application logic, integrations, deployment processes, and the behavior of the Kubernetes control plane and node OS in a configuration that closely resembles production. Risks arising from unavoidable differences will be mitigated through thorough component testing, robust monitoring, and well-defined operational procedures for production.

This design leverages Infrastructure as Code (IaC) principles, GitOps workflows, and best-of-breed technologies to ensure robustness and operational efficiency.

### Key Objectives

- **Security & Compliance**: Adhere strictly to WebTrust for CAs and CA/Browser Forum Baseline Requirements (BRs) and Network Security Requirements (NSRs).
- **Automation**: Automate infrastructure provisioning, application deployment, and configuration management.
- **Scalability & Reliability**: Design for horizontal scalability and high availability of Boulder components.
- **Dev-Prod Parity**: Ensure consistency across development, staging, and production environments.
- **Operational Efficiency**: Streamline deployment, updates, and maintenance through modern tooling.

## 2. Architecture Principles

- **Kubernetes-centric**: Kubernetes will be the core orchestration platform for Boulder microservices.
- **Infrastructure as Code (IaC)**: All infrastructure and application configurations will be defined declaratively using code (Terraform, Helm, Kustomize) and version-controlled in Git.
- **GitOps**: FluxCD will be used for GitOps, ensuring that the Git repository is the single source of truth for both infrastructure and application state.
- **Security Best Practices**:
  - **Principle of Least Privilege**: Components will have the minimum necessary permissions.
  - **Defense in Depth**: Multiple layers of security controls will be implemented.
  - **Secure by Default**: Security configurations will be strict by default.
  - **Immutable Infrastructure**: Deployments should be immutable where possible.
- **Compliance-driven Design**: Security and compliance requirements will directly inform architectural decisions.
- **Vendor Neutrality (where practical)**: Favor open standards and avoid vendor lock-in where feasible, while leveraging GCP-managed services for operational efficiency where appropriate for non-core CA functions.
- **Modularity & Reusability**: Design components and configurations to be modular and reusable.

## 3. Technology Stack

- **Orchestration**: For persistent Staging environments, self-managed Kubernetes clusters will be deployed on Google Compute Engine (GCE) VMs. This approach is chosen to better test the full infrastructure stack and maintain closer parity with the bare-metal production environment.
- **Container Runtime**: containerd.
- **Operating System (Nodes)**: Talos OS will be deployed on GCE VMs for the staging environment and on bare-metal for production.
- **Infrastructure Provisioning**: Terraform.
- **GitOps**: FluxCD.
- **Configuration Management**: Kustomize for environment-specific configurations, Helm for packaging Boulder applications.
- **Secrets Management**:
  - **HSM Integration**: Thales Luna Network HSMs will be used for CA private keys.
  - **Application Secrets**: HashiCorp Vault will be used for other application secrets like API keys and database credentials. A Vault cluster will be deployed and the Vault Agent Injector or CSI driver will be used to inject secrets into Boulder pods.
- **Networking**:
  - **CNI**: Calico will be used if the default CNI does not suffice for Network Security Requirements (NSR) compliance.
  - **Service Mesh**: The decision to implement a service mesh (Istio or Linkerd) is deferred until a thorough analysis of its benefits versus its complexity is completed.
  - **Ingress**: A suitable Ingress controller like Nginx or Traefik will be deployed.
- **Databases (External to K8s)**:
  - **MariaDB/MySQL**: Google Cloud SQL for MariaDB/MySQL.
  - **Redis**: Google Cloud Memorystore for Redis.
- **Logging & Monitoring**:
  - **Logging**: Google Cloud Logging. Logs will be collected from containers by Fluentd or a similar shipper.
  - **Monitoring**: Google Cloud Monitoring and Prometheus/Grafana.
  - **Alerting**: Google Cloud Monitoring or Alertmanager.
- **CI/CD**: GitHub CI/CD.
- **Container Registry**: Google Artifact Registry.
- **Code Quality & Security**: SonarQube, Trivy (for container scanning).

## 4. Kubernetes Cluster Design

### Environment Strategy and Isolation

A tiered environment strategy will be adopted to balance development velocity with stability. Each environment will be strictly isolated.

- **Ephemeral Environments**:
  - **Purpose**: Internal development and testing in complete isolation.
  - **Implementation**: For every pull request, the CI/CD system will automatically provision a complete, ephemeral copy of the application. These environments enable rapid iteration without impacting other testing activities.
- **Staging Environment**:
  - **Purpose**: A combined, high-fidelity environment serving two primary functions:
    1. **Final Release Validation:** Serves as the internal quality gate for testing Boulder release candidates on production-like infrastructure.
    2. **Partner Integration:** Provides a stable integration endpoint for external clients.
  - **Implementation**: A persistent, production-replica cluster. Given that the service runs battle-tested vanilla Boulder code, the risk of application-level instability is low. The primary focus is validating infrastructure compatibility. A clear communication process (e.g., status page, mailing list) will be used to announce testing windows where the environment might be temporarily unstable.
- **Production Environment**:
  - **Purpose**: Live service for end-users.
  - **Implementation**: A highly-available, multi-regional bare-metal cluster. Receives only code that has passed all previous gates.
- **Networking Configuration**:
  - **VPC Native Clusters**: Utilize GKE's VPC-native networking.
  - **Network Policies**: Implement strict, default-deny network policies to control traffic flow between components.
  - **Egress Control**: Use Cloud NAT and Firewall Rules to control and log outbound traffic.
  - **Ingress Control**: Secure Ingress points with Google Cloud Armor WAF.
- **Security Hardening**:
  - Apply relevant CIS benchmarks for Kubernetes.
  - Use Workload Identity to securely grant Kubernetes service accounts access to Google Cloud resources.
  - Define strict securityContext for Pods and containers (e.g., runAsNonRoot: true, readOnlyRootFilesystem: true).
  - Enforce pod security standards using PodSecurityAdmission (PSA) or OPA/Gatekeeper.
  - Perform regular security audits.

## 5. Boulder Application Deployment

A custom Helm chart will be developed to deploy Boulder components. It will manage Deployments/StatefulSets, Services, ConfigMaps, Secrets, NetworkPolicies, Probes, Resource requests/limits, and Pod Disruption Budgets.

### HSM Integration Strategy

- **Staging and Production**: The Boulder CA component will integrate directly with Thales Luna Network HSMs using the Luna Client PKCS#11 library.
- **Local Development**: This environment will use a mock HSM setup, consisting of a PKCS#11 proxy with SoftHSM in a separate container.
- **Security**: All network communication to the HSMs must be encrypted and authenticated.

## 6. Database and State Management

- **MariaDB (Cloud SQL)**: Used for core Boulder data and accessed exclusively by the Storage Authority (SA) component. Other components interact with the database via gRPC calls to the SA. HA configuration, regular backups, and Point-in-Time Recovery (PITR) will be configured.
- **Redis (Memorystore)**: Used for the nonce service, rate limiting, and storing OCSP responses. It will be accessed via private IP and have an appropriate HA configuration for Staging and Production.
- **Stateless Boulder Components**: All Boulder components will be designed to be stateless within Kubernetes, relying on the external Cloud SQL and Memorystore for persistence to simplify scaling and upgrades.

## 7. Secrets Management

- **CA Private Keys (HSM)**: Keys will remain securely within the Thales Luna HSMs. Access is controlled by HSM client authentication. The CA Kubernetes pods will require secure network access to the HSMs.
- **Application Secrets (HashiCorp Vault)**: For secrets like database credentials and API keys, a Vault cluster will be deployed. The Vault Agent Injector or CSI driver will be used to inject secrets into Boulder pods. Rotation policies for these secrets will be implemented.

## 8. Networking and Traffic Flow

- **Ingress**: The WFE and OCSP Responder will be publicly exposed via a deployed Ingress controller, secured with Google Cloud Armor.
- **Egress**: The VA requires controlled outbound internet access for validation checks, managed via Cloud NAT and egress NetworkPolicies. All other components will have restricted egress.
- **Internal Traffic**: Communication will be governed by strict, default-deny NetworkPolicies. Boulder components will communicate internally using gRPC over Kubernetes ClusterIP services.
- **HSM Network**: A secure, isolated network path will be established from the CA pods to the HSMs, potentially using VPC peering or dedicated interconnects.

## 9. Observability (Logging, Monitoring, Alerting)

- **Logging**: Application logs written to stdout/stderr will be collected by Fluentd and forwarded to Google Cloud Logging. Structured (JSON) logging is preferred.
- **Monitoring**: System and application metrics will be monitored. Boulder application metrics will be exposed in Prometheus format and scraped by a Prometheus server with Grafana for dashboards.
- **Alerting**: Critical alerts will be defined in Google Cloud Monitoring or Alertmanager for CA health, database/Redis performance, service availability, issuance failures, HSM connectivity, and security events.

## 10. Scalability and High Availability

- **Horizontal Pod Autoscaler (HPA)**: HPA will be configured for stateless Boulder components based on CPU/memory utilization.
- **Cluster Autoscaler**: A cluster autoscaler compatible with GCE will be configured to manage node counts.
- **Pod Disruption Budgets (PDBs)**: PDBs will ensure service availability during voluntary disruptions.
- **Multi-Zone/Regional Clusters**: A true production environment will require multiple regional availability zones or physical datacenters. The staging cluster will be deployed across multiple zones for HA.
- **Database/Redis HA**: HA configurations will be used for Cloud SQL and Memorystore.
- **Boulder CA Component**: While redundancy is required, the specific pod-level HA strategy (e.g., active/passive) has not yet been chosen and is pending further investigation. HSM availability is critical.

## 11. Backup and Disaster Recovery

- **Database Backup (Cloud SQL)**: Automated daily backups, on-demand snapshots, and Point-in-Time Recovery will be enabled. Backups will be replicated to another region.
- **Redis Backup (Memorystore)**: The need for backups will be evaluated based on RPO/RTO and data regeneration capabilities.
- **HSM Private Keys**: Keys will be backed up using standard Thales Luna HSM procedures and stored securely with multi-person control.
- **Kubernetes State (etcd)**: Responsibility for etcd backup and recovery for the self-managed cluster lies with the operations team, using mechanisms provided by Talos OS. The primary DR strategy remains recreation from IaC and GitOps.
- **Configuration and Artifacts**: All configurations (Terraform, Helm, Kustomize) are stored in Git. Container images and Helm charts are stored in Google Artifact Registry.
- **DR Site & Drills**: A DR plan will be defined to restore service in a secondary location, and periodic DR drills will be conducted.

## 12. Local Development Environment

The local environment is for integration testing of CA components in a mock setup. It will use KinD (Kubernetes in Docker) to provision a local, CNCF-conformant Kubernetes cluster.

Tilt is recommended to orchestrate the local workflow. A Tiltfile will define how to deploy all Boulder microservices and their mock dependencies—including a mock HSM (SoftHSM with a PKCS#11 proxy)—in the correct order using the project's standard Helm charts. Tilt provides a unified UI for observing logs and the status of all services, simplifying diagnosis during testing.

This setup is strictly for local development and testing; deployments to staging and production will use the defined GitHub CI/CD and FluxCD pipeline.

## 13. Future Considerations

- **Service Mesh (Istio/Linkerd)**: A decision on implementing a service mesh for advanced mTLS and traffic management is currently deferred a thorough analysis of its benefits versus its complexity is completed.
- **Advanced VA Egress Filtering**: More granular control over VA outbound traffic may be considered if needed.
- **Automated Compliance Checks**: Tools like OPA/Gatekeeper may be used to continuously enforce compliance policies in the cluster.
- **KMS Integration**: Encrypting etcd for the self-managed cluster using a KMS (like Google Cloud KMS) should be investigated.
