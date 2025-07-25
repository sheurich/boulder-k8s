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
  - [ ] **Task-8.6: Boulder Microservices Decomposition**: Break down the monolithic Boulder deployment into individual microservices.
    - [ ] **Task-8.6.1: Create Boulder Service Deployments**: Deploy WFE, RA (2 instances), VA (2 instances), CA (2 instances), SA (2 instances), Publisher (2 instances), OCSP Responder, Remote VA (3 instances), Nonce Services (3 instances) as separate Kubernetes Deployments
    - [ ] **Task-8.6.2: Configure Inter-service TLS**: Set up mutual TLS certificates for all gRPC communication between Boulder services using test PKI infrastructure
    - [ ] **Task-8.6.3: Implement Service Discovery**: Configure Consul service registration for all Boulder services with proper SRV records and health checks
    - [ ] **Task-8.6.4: Configure Redis Sharding**: Set up 4 Redis instances with fixed IP addresses for OCSP (2 instances) and rate limiting (2 instances) functionality
    - [ ] **Task-8.6.5: Deploy Challenge Test Server**: Implement chall-test-srv as a Kubernetes service to handle HTTP-01, DNS-01, and TLS-ALPN-01 challenges
    - [ ] **Task-8.6.6: Deploy Test Support Services**: Add CT test server, AIA test server, S3 test server, Akamai test server, and Pardot test server
    - [ ] **Task-8.6.7: Configure Network Policies**: Create NetworkPolicies to simulate the three Docker networks (bouldernet, publicnet, publicnet2) for security isolation
    - [ ] **Task-8.6.8: Set up PKI Certificate Infrastructure with cert-manager**: Install cert-manager and configure ClusterIssuer for automated inter-service TLS certificate management
    - [ ] **Task-8.6.9: Configure SoftHSM Integration**: Mount SoftHSM tokens and PKCS#11 configuration files for CA cryptographic operations
    - [ ] **Task-8.6.10: Create Service Configuration Maps**: Generate comprehensive ConfigMaps containing all Boulder service configurations adapted from test/config/ directory
  - [ ] **Task-8.7: Integration Test Execution**: Create Kubernetes Jobs to run Boulder's integration test suite
    - [ ] **Task-8.7.1: Database Initialization Job**: Create Job to initialize Boulder database schema and migrations
    - [ ] **Task-8.7.2: Service Dependency Health Checks**: Implement proper startup ordering and health checks for all services
    - [ ] **Task-8.7.3: Integration Test Runner**: Port boulder/test/integration-test.py to run as Kubernetes Job with proper service dependencies
    - [ ] **Task-8.7.4: Go Integration Tests**: Configure and run Boulder's Go integration tests (test/integration/) as Kubernetes Jobs
    - [ ] **Task-8.7.5: Python Integration Tests**: Configure and run Boulder's Python integration tests (v2_integration.py) as Kubernetes Jobs
  - [ ] **Task-8.8: Helm Chart Integration**: Update the Helm chart structure to support the complete Boulder integration test environment
    - [ ] **Task-8.8.1: Values Schema Definition**: Define comprehensive values.yaml schema for all Boulder services and dependencies
    - [ ] **Task-8.8.2: Template Reorganization**: Restructure Helm templates to support modular service deployment
    - [ ] **Task-8.8.3: Dependency Management**: Configure Helm chart dependencies for infrastructure services
    - [ ] **Task-8.8.4: Integration Test Hook**: Implement Helm test hooks for running integration tests post-deployment

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
