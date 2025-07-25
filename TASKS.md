# Project Tasks

This file tracks high-level tasks and the project backlog. Detailed tasks should be created as GitHub Issues.

## MVP: Local Development Environment

This milestone focuses on creating a minimal, end-to-end setup for running Boulder on a local machine. The environment will be provisioned with Kubernetes-in-Docker (`kind`) and Helm. It will use a `DEVELOPMENT` configuration, suitable for running integration tests.

- [x] **Task-4: Provision Local Kubernetes Cluster**
  - Create a script to provision a local Kubernetes cluster using `kind`.
  - The script will also load the Boulder Docker image into the cluster nodes.

- [x] **Task-5: Create Helm Chart for Boulder**
  - Develop a Helm chart to deploy Boulder and its dependencies.
  - The chart will be configured for the `DEVELOPMENT` environment.

- [x] **Task-6: Implement Mock HSM**
  - Integrate a software-based mock HSM for development and testing.
  - This will be deployed as part of the Helm chart.

- [x] **Task-7: Configure for Integration Testing**
  - Configure the Boulder deployment to run its built-in integration tests.
  - Document the process for running the tests.

- [x] **Task-8: Update Test Scripts**
  - Update `test` and `test.go` to perform a full integration test using `kind` and `helm`.

## In-Flight

- [ ] **Task-9: Configure Core Components**
  - Configure and deploy Boulder's core components (WFE, RA, CA, SA, etc.).

## Backlog
- [ ] Configure Boulder for production usage (e.g., rate limits, certificate profiles).
- [ ] Integrate Boulder with the chosen database backend.
- [ ] Integrate with a real HSM.
- [ ] Add support for multiple cloud providers (AWS, GCP, Azure).
- [ ] Set up a comprehensive monitoring and alerting stack.
