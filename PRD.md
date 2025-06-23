# **Product Requirements Document: Boulder Kubernetes Migration**

## **1. Overview**

This document outlines the requirements for migrating the Boulder project from its current Docker Compose-based development environment to a production-ready, scalable, and maintainable Kubernetes environment. The primary goal is to create a robust, secure, and automated platform for the development, testing, and deployment of the Boulder application.

## **2. Project Goal**

To systematically migrate all components of the Boulder application to a Kubernetes cluster, ensuring the new environment meets production standards for stateful data management, security, observability, and developer workflow automation.

## **3. Phases & Requirements**

### **Phase 1: Inventory & Tag**

- **Goal:** Create a complete and structured inventory of all application components from the existing Docker Compose setup.
- **Requirements & Deliverables:**
  - A CSV file (compose-inventory.csv) detailing each service, its image, ports, volumes, networks, environment variables, dependencies, and entrypoint.
  - A JSON file (tags.json) mapping service names to functional tags (e.g., role:database, stateful, needs-init).

### **Phase 2: YAML Scaffold**

- **Goal:** Generate initial Kubernetes manifests and confirm that all services can start successfully in a local Kubernetes cluster.
- **Requirements & Deliverables:**
  - A directory of raw Kubernetes Deployment and Service YAML files for each application component, generated via kompose.
  - Verification that all generated pods can reach a Running state in a local cluster.

### **Phase 3: Stateful Operators**

- **Goal:** Replace basic stateful service deployments with robust, operator-managed instances for MariaDB and Redis to ensure high availability and data persistence.
- **Requirements & Deliverables:**
  - A fully operational, multi-instance Redis cluster managed by a Redis Operator, with dedicated PersistentVolumeClaims (PVCs) for each instance.
  - A running MariaDB instance managed by a MariaDB Operator.
  - Completed deployment manifests for all Boulder microservices (boulder-sa, boulder-ca, boulder-ra, boulder-va, boulder-wfe2, nonce-service, ocsp-responder) based on the architecture defined in startservers.py.
  - A functional solution for building the Boulder service binaries, either via an init container or a modified build command.

### **Phase 4: Secrets & PKI**

- **Goal:** Secure the application by managing all secrets and the complex Public Key Infrastructure (PKI) bootstrapping process using Kubernetes-native patterns.
- **Requirements & Deliverables:**
  - A Dockerfile and bootstrap script for an Init Container capable of handling the PKI setup with SoftHSMv2.
  - Kubernetes Secret manifests for all sensitive values.
  - A cert-manager Issuer and Certificate manifests to enable mutual TLS (mTLS) for pod-to-pod communication.

### **Phase 5: Dev Inner-Loop**

- **Goal:** Replace the manual docker-compose up workflow with a fast, automated inner-loop for Kubernetes development.
- **Requirements & Deliverables:**
  - A skaffold.yaml or Tiltfile that fully manages the build, deployment, and file-syncing lifecycle for local development.

### **Phase 6: CI/CD Pipeline**

- **Goal:** Automate the building, testing, and deployment of the application to a Kubernetes environment.
- **Requirements & Deliverables:**
  - A version-controlled Helm chart or Kustomize base containing all Kubernetes manifests.
  - A GitHub Actions workflow that builds, tests, and deploys the application to a staging environment, and packages the chart for release.

### **Phase 7: Observability**

- **Goal:** Integrate a complete observability stack for metrics, logging, and tracing.
- **Requirements & Deliverables:**
  - A deployed kube-prometheus-stack (Prometheus and Grafana) for metrics collection.
  - A deployed Jaeger instance for distributed tracing.
  - An imported and configured Grafana dashboard for Boulder.
  - Pull requests demonstrating OpenTelemetry instrumentation added to the Go microservices.

### **Phase 8: Hardening & Policies**

- **Goal:** Secure the cluster environment and improve application resilience by implementing security best practices.
- **Requirements & Deliverables:**
  - Updated Deployment manifests including livenessProbe, readinessProbe, and startupProbe.
  - A set of NetworkPolicy manifests to enforce a "deny-by-default" traffic policy.
  - A set of RBAC manifests (ServiceAccount, Role, RoleBinding) to enforce the principle of least privilege for each service.

### **Phase 9: Testing & Rollout**

- **Goal:** Ensure the application is production-ready through rigorous testing and execute a safe, staged rollout.
- **Requirements & Deliverables:**
  - HorizontalPodAutoscaler (HPA) and PodDisruptionBudget (PDB) manifests.
  - A comprehensive RUNBOOK.md detailing deployment, rollback, and disaster recovery procedures.
  - A proven and tested rollback plan.
