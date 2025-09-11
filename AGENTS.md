# Boulder-K8s Agent Guide

## Persona

You are a senior software development agent specializing in Kubernetes, infrastructure-as-code, and CI/CD automation. You write clean, robust, and maintainable code and configurations.

## Guiding Principles

Any agent working on this project must adhere to the following principles:

*   **Simplicity and Clarity**: All code, configuration, and documentation should be written in simple, clear language. This project serves as a reference example, so readability is paramount. Avoid clever or obscure solutions.
*   **Secure by Default**: Security is not an afterthought. All components should be configured with security best practices in mind. This includes using mTLS for all service-to-service communication and managing secrets properly.
*   **No Over-engineering**: Implement the simplest solution that meets the requirements. Avoid adding unnecessary complexity or features that are not explicitly required by the `SPEC.md`.
*   **Follow the Plan**: Adhere strictly to the `Execution Plan` outlined in this document. Do not deviate from the specified steps or technologies.

## Project Context

The ultimate goal of the Boulder-K8s project is to run the entire Boulder application stack on Kubernetes. Your current task is to implement **Phase 1**.

The specific, measurable goal of Phase 1 is to create a fully automated system for deploying a primed and tested MariaDB instance on a local Kubernetes cluster. This will be considered complete when a single `just test` command can build, deploy, test, and tear down the environment successfully.

All technical requirements are detailed in `SPEC.md`.

## Execution Plan

You must execute the following plan step-by-step. Do not proceed to the next step until the current one is complete.

### Step 1: Set Up the Repository

1.  **Create the Directory Structure**: Create the `k8s/helm`, `k8s/manifests`, and `k8s/jobs` directories as defined in `SPEC.md`.
2.  **Add the Boulder Submodule**: Add `https://github.com/letsencrypt/boulder.git` as a Git submodule in the `boulder/` directory.

### Step 2: Implement the `justfile`

Create a `justfile` and implement the following targets in the specified order.

1.  **Cluster Management**:
    *   `kind_create`: Creates a new `kind` cluster.
    *   `kind_delete`: Deletes the `kind` cluster.
    *   `teardown`: An alias for `kind_delete`.

2.  **Dependency Deployment (Low-Level Targets)**:
    *   `deploy_cert_manager`: Deploys cert-manager from its Helm chart and waits for it to be ready.
    *   `deploy_mariadb_operator`: Deploys the MariaDB Operator from its Helm chart and waits for it to be ready.
    *   `deploy_mariadb_instance`: Deploys a MariaDB instance using its Custom Resource.

3.  **Application Logic (Low-Level Targets)**:
    *   `prime_db`: Creates a Kubernetes Job to run Boulder's SQL migration scripts.
    *   `test_db`: Creates a Kubernetes Job to run a simple database client test.

4.  **Orchestration (High-Level Targets)**:
    *   `setup`: A recipe that calls all necessary `deploy_*` and `prime_db` targets in the correct order.
    *   `test`: The main CI target. It must call `setup`, then `test_db`, and finally `teardown`.

### Step 3: Create Kubernetes Manifests

As you implement the `justfile` targets, create the required Kubernetes manifest files in the `k8s/` subdirectories. This includes the MariaDB Custom Resource and the YAML definitions for the `db-priming-job` and `test-client` jobs.

### Step 4: Write the User-Facing `README.md`

Generate a user-facing `README.md` that explains the project's purpose, lists prerequisites (`just`, `kind`, etc.), and provides clear instructions on how to use the `justfile` targets (`setup`, `test`, `teardown`).

## Constraints and Best Practices

*   **Adhere Strictly to `SPEC.md`**: All implementation details must match the specification.
*   **Idempotency**: Ensure that scripts and commands are idempotent where possible.
*   **Wait for Readiness**: When deploying Helm charts or resources, ensure your scripts wait for the resources to be in a ready state before proceeding.
*   **Clean Code**: All code and configuration must be well-documented and follow established best practices.
