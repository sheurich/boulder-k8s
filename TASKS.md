# Project Tasks

This file tracks high-level tasks and the project backlog. Detailed tasks should be created as GitHub Issues.

## Phase 1: Project Setup & Foundational IaC

- [x] Task-1: Define initial project structure and documentation.
- [x] Task-2: Incorporate MVP Dockerfile for Boulder.
- [x] Task-3: Incorporate MVP test script for the Boulder Docker image.
- [ ] Task-4: Create initial Helm chart for deploying Boulder to Kubernetes.
- [ ] Task-5: Implement a mock HSM for local development.

## Phase 2: Core CA Functionality

- [ ] Configure and deploy Boulder's core components (WFE, RA, CA, SA, etc.).
- [ ] Configure Boulder for production usage (e.g., rate limits, certificate profiles).
- [ ] Integrate Boulder with the chosen database backend.

## Backlog

- [ ] Integrate with a real HSM.
- [ ] Add support for multiple cloud providers (AWS, GCP, Azure).
- [ ] Set up a comprehensive monitoring and alerting stack.
