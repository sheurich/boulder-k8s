# Project Tasks

This file tracks high-level tasks and the project backlog, organized by milestones. Detailed tasks should be created as GitHub Issues.

## Milestone 1: Foundational Local Development Environment

This milestone focuses on creating a minimal, end-to-end setup for running and testing Boulder on a local machine using `kind` and Helm.

- [x] **Task-1: Project Scaffolding**: Set up the repository, initial documentation, and directory structure.
- [x] **Task-2: Basic Docker Image**: Create a `boulder.dockerfile` that can build a runnable Boulder image.
- [x] **Task-3: Provision Local Kubernetes Cluster**: Create a script to provision a local `kind` cluster.
- [x] **Task-4: Basic Helm Chart**: Develop a Helm chart to deploy Boulder for a `DEVELOPMENT` configuration.
- [x] **Task-5: Helm Smoke Test**: Implement a basic `helm test` to verify the Boulder container can be deployed successfully.
- [x] **Task-6: Refine Test Script**: Improve the end-to-end `test` script with dependency checks, configuration variables, and optional cleanup.
- [x] **Task-7: Implement Mock HSM**: Integrated as part of the broader integration testing setup.
- [ ] **Task-8: Configure for Integration Testing**: Configure the Boulder deployment to run its built-in integration tests against the local `kind` cluster. This requires deploying and configuring several dependencies identified from the upstream Boulder development environment.
  - [x] **Task-8.1: Deploy Database Services**: Add MariaDB and ProxySQL to the Helm chart.
  - [x] **Task-8.2: Deploy Redis**: Add Redis to the Helm chart for caching and rate limiting.
  - [x] **Task-8.3: Deploy Consul**: Add Consul to the Helm chart for service discovery.
  - [x] **Task-8.4: Deploy Jaeger**: Add Jaeger to the Helm chart for distributed tracing.
  - [ ] **Task-8.5: Configure SoftHSM**: Configure the Boulder deployment to use the software-based mock HSM.
  - [x] **Task-8.6: Final Integration**: Update the Boulder configuration in the Helm chart to use all deployed dependencies and execute the integration test suite.

## Milestone 2: Core CA Functionality

This milestone focuses on deploying a fully functional, multi-component Boulder instance that can perform its core CA duties.

- [ ] **Task-9: Decompose Boulder into Components**: Update the Helm chart to deploy Boulder's individual services (WFE, RA, VA, CA, SA, etc.) as separate Kubernetes resources.
- [ ] **Task-10: Database Integration**: Integrate Boulder with a database backend (e.g., MariaDB) deployed within the cluster.
- [ ] **Task-11: Configure Ingress**: Set up Ingress resources to expose public-facing services (ACME, OCSP).
- [ ] **Task-12: End-to-End Certificate Issuance**: Create a test to validate the full certificate issuance flow using an ACME client against the local deployment.

## Milestone 3: Production Readiness

This milestone focuses on the security, operational, and compliance requirements for running a publicly-trusted CA.

- [ ] **Task-13: Real HSM Integration**: Develop the IaC to integrate with a production-grade HSM (e.g., using PKCS#11).
- [ ] **Task-14: Security Hardening**:
  - Implement strict NetworkPolicies between components.
  - Define and apply Pod Security Standards.
  - Configure RBAC with the principle of least privilege.
  - Implement a robust secrets management strategy (e.g., HashiCorp Vault).
- [ ] **Task-15: Monitoring and Alerting**: Set up a monitoring stack (e.g., Prometheus, Grafana) and define alerts for key SLIs.
- [ ] **Task-16: Centralized and Auditable Logging**: Implement a logging solution (e.g., EFK or Loki stack) to aggregate logs from all components for audit and debugging.
- [ ] **Task-17: Production Configuration**: Configure Boulder for production usage (e.g., rate limits, certificate profiles).

## Milestone 4: Multi-Platform Portability

This milestone focuses on making the solution deployable across different environments, including major cloud providers and bare metal.

- [ ] **Task-18: Terraform for Cloud Infrastructure**: Create Terraform modules to provision managed Kubernetes clusters (EKS, GKE, AKS) and their dependencies (VPCs, IAM roles, etc.).
- [ ] **Task-19: Bare-Metal Deployment Guide**: Document the process and provide scripts for deploying on a bare-metal Kubernetes cluster.
- [ ] **Task-20: CI/CD Pipeline**: Create a robust CI/CD pipeline to automate testing and deployment to different environments.
