# Boulder K8s - Phase 1 Specification

## 1. Overview

This document provides the technical specification for Phase 1 of the Boulder Kubernetes project.

### 1.1. Long-Term Goal

The ultimate goal of this project is to run the entire Boulder application stack on Kubernetes for production, staging, and integration testing environments.

### 1.2. Phase 1 Goal

The specific, measurable goal of Phase 1 is to create a fully automated system for deploying a primed and tested MariaDB instance on a local Kubernetes cluster. This serves as the foundational data layer required before any Boulder application services can be deployed. This phase will be considered complete when a `just test` command can successfully create a cluster, deploy all dependencies, prime the database, run verification tests, and clean up, all in one command.

## 2. Technology Stack

The following tools are required for this phase:

- **Local Kubernetes Cluster**: `kind`
- **Package Management**: Helm
- **Certificate Management**: cert-manager
- **Database**: MariaDB Operator for Kubernetes
- **Task Runner**: `just`
- **Boulder Source Code**: A Git submodule of the official Boulder repository.

## 3. Repository Structure

The project will be a monorepo with the following top-level structure:

```
boulder-k8s/
├── boulder/            # Git submodule of the official Boulder repo
├── k8s/                # All Kubernetes manifests and configurations
│   ├── helm/           # Helm chart configurations/values
│   ├── manifests/      # Core YAML manifests (e.g., MariaDB custom resource)
│   └── jobs/           # YAML for Kubernetes Jobs (e.g., db-priming, test-client)
├── justfile            # Automation recipes for setup, testing, and teardown
├── PROMPT.md           # The prompt for the development agent
├── README.md           # Project overview and user guide
└── SPEC.md             # This specification document
```

## 4. Implementation Plan

The entire workflow will be orchestrated via a `justfile`.

### 4.1. Boulder Source Code Integration

The official Boulder repository must be included as a Git submodule in the `boulder/` directory. This ensures that the SQL migration scripts are version-controlled alongside the Kubernetes configurations and can be easily updated.

**Action Item**: Add `https://github.com/letsencrypt/boulder.git` as a submodule to the `boulder` directory.

### 4.2. Automation with `justfile`

A `justfile` will be the main entry point for all operations. It must contain the following targets:

#### High-Level Targets:

- `setup`: A recipe that depends on all necessary `deploy_*` targets to bring up a fully primed database.
- `test`: The primary target for CI. It must depend on `setup`, then run the `test_db` target, and finally call the `teardown` target, ensuring a clean exit.
- `teardown`: Destroys the `kind` cluster.

#### Low-Level Targets:

- `kind_create`: Creates a new `kind` cluster.
- `kind_delete`: Deletes the `kind` cluster.
- `deploy_cert_manager`: Deploys cert-manager from its official Helm chart. Must wait for the deployment to be ready before exiting.
- `deploy_mariadb_operator`: Deploys the MariaDB Operator from its official Helm chart. Must wait for the deployment to be ready.
- `deploy_mariadb_instance`: Deploys an instance of MariaDB using the operator's Custom Resource. This will be a simple, single-replica instance for now.
- `prime_db`: Creates and runs a Kubernetes Job that executes the Boulder SQL migration scripts against the MariaDB instance.
- `test_db`: Creates and runs a Kubernetes Job that acts as a test client to verify the database setup.

### 4.3. Database Priming

The database must be primed with Boulder's schema, database, and users.

- A Kubernetes Job named `db-priming-job` will be created from a YAML file in `k8s/jobs/`.
- This Job's pod will have an `init` container responsible for running the SQL migration scripts.
- The `boulder/sa/db/migrations` directory from the submodule must be mounted into the `init` container as a volume.
- The `init` container will use a standard MariaDB client image.

## 5. Verification

The `test_db` Kubernetes Job will be responsible for verifying that the database is correctly primed and ready for use.

- The Job will use a MariaDB client container.
- The client will connect to the MariaDB instance.
- **Success Criteria**: The test client must successfully execute the command `SHOW TABLES;` and receive a non-empty result, proving that the database schema has been created.
