# AI Agent Developer Guidelines

This document provides guidelines for AI software development agents contributing to the Boulder on Kubernetes (boulder-k8s) project - a complete Infrastructure as Code monorepo for WebPKI Certification Authority deployment.

## 1. Overview

This repository is managed by human operators supervising AI agents. The end-to-end process for operators is documented in `docs/agent-workflow.md`. As an agent, your role is to follow the instructions in a given task, adhere to the guidelines below, and produce code and documentation changes for a production-ready CA deployment system.

**Project Goal**: Create a complete Infrastructure-as-Code monorepo that can deploy Boulder CA instances across LOCAL (Docker+kind), CLOUD (VMs+Talos+K8s), and METAL (bare-metal+Talos+K8s) environments in both TEST and PRODUCTION modes.

## 2. Core Principles

- **Understand the Goal**: Before writing any code, ensure you understand the requirements from the task description. If anything is ambiguous, ask for clarification.
- **Follow Instructions**: Adhere strictly to the instructions given in the task. Do not perform work outside the scope of the request.
- **Test Compliance is Non-Negotiable**: All changes MUST pass the test suite (`./test`). This is a hard requirement for all contributors.
- **Boulder Microservices Architecture**: Understand that Boulder runs as multiple microservices using a single container image with different commands.
- **Use Best Practices**: Always use software development best practices for the languages and tools involved.
- **Respect Existing Code**: Follow the existing conventions, style, and architecture of the project.

## 3. Project Architecture Understanding

### 3.1 Boulder Microservices
Boulder CA software is deployed as separate Kubernetes microservices, all using the **same container image** but different command arguments:

- **Web Front End (WFE)**: ACME API endpoint (command: `boulder-wfe2`)
- **Registration Authority (RA)**: Account/order management (command: `boulder-ra`)  
- **Validation Authority (VA)**: Domain validation (command: `boulder-va`)
- **Certificate Authority (CA)**: Certificate issuance (command: `boulder-ca`)
- **Storage Authority (SA)**: Database operations (command: `boulder-sa`)
- **Publisher**: Certificate transparency (command: `boulder-publisher`)
- **Remote VA**: Distributed validation (command: `remoteva`)
- **Nonce Service**: Cryptographic nonces (command: `nonce-service`)

### 3.2 Deployment Environments
- **LOCAL**: Developer laptop/CI with Docker+kind, SoftHSM
- **CLOUD**: VMs with Talos+K8s, cloud or hardware HSMs  
- **METAL**: Bare-metal with Talos+K8s, hardware HSMs

### 3.3 Operational Modes
- **TEST**: Development/integration testing
- **PRODUCTION**: Live CA operations with public trust

## 4. Workflow

1.  **Receive Task**: A task will be assigned to you, usually via a GitHub issue.
2.  **Analyze and Plan**:
    -   Read the task description carefully.
    -   Understand how the change fits into the LOCAL/CLOUD/METAL deployment model.
    -   Identify the files that need to be changed. If you need to edit files not provided in the context, ask for them by their full path.
    -   Formulate a step-by-step plan to implement the required changes.
3.  **Implement Changes**:
    -   Keep changes small and focused. One logical change per commit.
    -   Ensure changes work across all supported environments where applicable.
    -   Follow the Boulder microservices architecture pattern.
4.  **Test Validation**: Ensure `./test` passes before considering the task complete.

## 5. Code Contribution

- **Code Style**: Follow established style guides for the relevant languages (e.g., PEP 8 for Python, `shfmt` for shell scripts).
- **Documentation**: Update documentation (e.g., `docs/architecture.md`, READMEs) when you make changes to the system's behavior or architecture.
- **Testing**: 
  - **CRITICAL**: The `./test` script must always pass on completion of each change.
  - When adding new features or fixing bugs, add or update tests to cover the changes.
  - After any code modification, run the full test suite to ensure that no regressions have been introduced.
- **Helm Charts**: Follow Helm best practices when modifying charts/boulder/ templates.
- **Container Strategy**: Remember that all Boulder services use the same container image with different commands.
- **Commit Hygiene**: All changes must be submitted with clear, descriptive commit messages. Commits should be atomic, representing a single logical change. The repository's history is an audit artifact.

## 6. Boulder-Specific Guidelines

### 6.1 Service Configuration
- Each Boulder microservice requires its own JSON configuration file
- Services communicate via gRPC with mutual TLS
- Consul is used for service discovery via SRV records
- Redis clustering is used for rate limiting functionality

### 6.2 HSM Integration
- TEST mode: Use SoftHSM for cryptographic operations
- PRODUCTION mode: Support hardware HSMs via PKCS#11
- CA services require PKCS#11 configuration files

### 6.3 Network Architecture
- Implement network policies to isolate Boulder internal traffic
- Public-facing services (WFE) need ingress configuration
- Support for multiple network zones (bouldernet, publicnet)

## 7. Communication

- **Clarity**: Be clear and concise in your communication.
- **Asking Questions**: If a requirement is unclear, ask specific questions to resolve the ambiguity.
- **Test Results**: Always mention test results when completing tasks.
- **Reporting Progress**: Provide updates on your progress as requested.
