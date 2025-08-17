# Prompt for Agent - Phase 1

> **Navigation:** See [`README.md`](README.md) for project overview | [`SPECp1.md`](SPECp1.md) for authoritative technical specifications | [`AGENTS.md`](AGENTS.md) for general agent guidelines

You are a highly skilled AI assistant with expertise in analyzing, understanding, and executing complex instructions for containerizing and deploying Boulder ACME CA services to Kubernetes. Your task is to carefully read, comprehend, and flawlessly execute the specific requirements outlined in this document and referenced specifications.

## Execution Approach

Approach this task with meticulous attention to detail, ensuring you:

- **Thoroughly parse all instructions, parameters, and constraints** specified in this file and `SPECp1.md`
- **Maintain strict adherence** to any formatting, style, or structural requirements indicated
- **Apply relevant domain knowledge** and best practices appropriate to Boulder ACME CA, Kubernetes, and containerization
- **Deliver comprehensive, accurate, and polished responses** that fully satisfy all stated objectives
- **Follow sequential steps** or procedural guidelines in the exact order presented
- **Incorporate specified examples, references, and contextual information** appropriately from `./reference/` materials

Begin executing the task immediately upon processing the file contents, demonstrating precision, creativity where appropriate, and complete alignment with the documented requirements.

## Primary Goal

Containerize and deploy Boulder microservices to a local Kubernetes cluster (kind). Enable Boulder's integration tests to run in this environment with full ACME CA functionality.

## Core Requirements

### Service Architecture

- Each Boulder service mode must be deployed in its own pod, using one container image with different commands
- Implement proper service dependencies and startup ordering as outlined in `AGENTS.md`
- Ensure strict adherence to Boulder's microservice architecture patterns

### Configuration Management

- Use ConfigMaps and Secrets for configuration management
- Maintain separation of concerns between environment-specific and application configuration
- Follow Boulder's existing configuration patterns and structure

### Service Discovery & Networking

- Use Kubernetes Services for inter-service discovery and communication
- Implement proper network policies and service mesh considerations
- Ensure ACME protocol endpoints are properly exposed

### Infrastructure Services

- Set up supporting services (Redis, PostgreSQL, HSM simulator) in-cluster
- Configure persistent storage where required
- Implement proper backup and recovery considerations

### Code Quality & Standards

- Write clean, reusable YAML manifests following Kubernetes best practices
- Use declarative configurations with proper resource management
- Group related manifests logically as specified in `AGENTS.md`

### Testing & Validation

- Write comprehensive integration test automation
- Verify service startup order and health checks
- Test complete ACME workflow end-to-end before considering deployment complete
- Ensure Boulder's existing integration tests pass in the Kubernetes environment

### Documentation & Maintenance

- Ensure documentation (`README.md`) stays current and comprehensive
- Follow project conventions outlined in `AGENTS.md`
- Maintain clear usage instructions and troubleshooting guidance

## Reference Materials

Leverage the following resources to inform your implementation:

- **`SPECp1.md`** - Complete phase 1 specification with detailed requirements
- **`./reference/BOULDER.md`** - Technical reference guide for Boulder setup and architecture
- **`./reference/boulder/`** - Complete Boulder source code repository
- **`./reference/boulder.wiki/`** - Design documents and implementation guides
- **`AGENTS.md`** - Project standards and naming conventions

## Success Criteria

Your implementation will be considered successful when:

1. All Boulder services are containerized and running in Kubernetes
2. Service dependencies are properly managed and startup order is correct
3. ACME CA functionality is fully operational
4. Integration tests pass without modification
5. Documentation is complete and accurate
6. Code follows all specified standards and conventions

Begin implementation immediately, working methodically through each requirement while maintaining the highest standards of technical excellence and documentation quality.
