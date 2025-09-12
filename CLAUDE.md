# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Boulder-K8s is a Kubernetes deployment system for the Boulder ACME CA. This repository focuses on **Phase 1**: creating a fully automated local development environment for deploying a production-ready MariaDB instance on Kubernetes as the foundational data layer.

## Architecture

The project follows a monorepo structure with clear separation of concerns:

```
boulder-k8s/
├── boulder/            # Git submodule of the official Boulder repository (✓ exists)
├── k8s/                # Kubernetes manifests and configurations (⚠️ needs creation)
│   ├── helm/           # Helm chart configurations/values
│   ├── manifests/      # Core YAML manifests (MariaDB CR, cert-manager resources)
│   └── jobs/           # Kubernetes Jobs (db-priming, test-client)
├── justfile            # Main automation orchestrator (⚠️ needs implementation)
├── Brewfile            # macOS development dependencies (✓ exists)
├── README.md           # User-facing documentation (✓ exists)
├── SPEC.md             # Technical specification (✓ exists)
└── AGENTS.md           # AI agent guidance (✓ exists)
```

## Development Commands

All development tasks are orchestrated via `just`. The justfile implements a hierarchical command structure:

**Current Implementation Status**: The justfile exists with target definitions but requires implementation of the actual commands for each target.

### Primary Commands
- `just setup` - Full environment setup (cluster + dependencies + database)
- `just test` - Complete CI workflow (setup → test → teardown)
- `just teardown` - Clean environment destruction

### Infrastructure Commands
- `just kind_create` - Create local Kubernetes cluster
- `just kind_delete` - Delete Kubernetes cluster
- `just deploy_cert_manager` - Install cert-manager via Helm
- `just deploy_mariadb_operator` - Install MariaDB Operator via Helm
- `just deploy_mariadb_instance` - Deploy MariaDB Custom Resource

### Application Commands
- `just prime_db` - Run Boulder SQL migrations via Kubernetes Job
- `just test_db` - Verify database setup via Kubernetes Job

## Prerequisites

**Required Tools:**
- `just` - Task runner and primary interface ([installation guide](https://github.com/casey/just#installation))
- `kind` - Local Kubernetes cluster ([installation guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))
- `kubectl` - Kubernetes CLI ([installation guide](https://kubernetes.io/docs/tasks/tools/install-kubectl/))
- `helm` - Package manager ([installation guide](https://helm.sh/docs/intro/install/))
- `git` - Version control (for submodule management)
- `docker` or `podman` - Container runtime (required by kind)

**Quick Setup for macOS:**
```bash
# Install via Homebrew using the provided Brewfile
brew bundle

# Initialize Boulder submodule (already completed)
git submodule update --init --recursive
```

**Manual Installation:**
See individual tool documentation linked above, or use the package manager for your platform.

## Technology Stack

**Kubernetes Components:**
- cert-manager - Certificate management (self-signed CA for mTLS)
- MariaDB Operator - Database lifecycle management
- MariaDB instance with mTLS security

## Security Architecture

The system implements mutual TLS (mTLS) for all database connections:

1. **Certificate Authority**: cert-manager creates a self-signed CA
2. **Server Certificate**: Issued to MariaDB instance
3. **Client Certificate**: Used by priming and testing jobs
4. **Authentication**: Database user `sa` requires valid client certificate (CN=boulder-client)
5. **No password-based authentication**

## Development Workflow

1. **Boulder Submodule**: The project includes Boulder as a Git submodule to access SQL migration scripts
2. **Database Priming**: Kubernetes Job executes Boulder migrations against mTLS-secured MariaDB
3. **Verification**: Test job validates database accessibility and schema presence
4. **Success Criteria**: `SHOW DATABASES;` must return `boulder_sa_integration`

## Implementation Guidelines

**Core Principles** (from AGENTS.md):
- **Simplicity and Clarity**: Readable, maintainable code
- **Secure by Default**: mTLS for all communications
- **No Over-engineering**: Minimal viable implementation
- **Follow the Plan**: Strict adherence to SPEC.md requirements

**Execution Order** (must be followed step-by-step):
1. Set up repository structure (`k8s/` directories) - **Next step needed**
2. Add Boulder submodule - **✓ Complete** 
3. Implement justfile targets (cluster → dependencies → application → orchestration) - **Pending**
4. Create Kubernetes manifests - **Pending**
5. Write user documentation - **✓ Complete**

## Key Files

- **SPEC.md**: Complete technical specification with detailed requirements
- **AGENTS.md**: Development principles and step-by-step execution plan
- **README.md**: User-facing documentation with prerequisites and usage
- **justfile**: All automation logic and command definitions
- **boulder/**: Git submodule containing SQL migration scripts

## Testing and Validation

The project's success is measured by a single command: `just test` must successfully:
1. Create and configure a complete Kubernetes environment
2. Deploy and secure MariaDB with mTLS
3. Execute Boulder database migrations
4. Verify database accessibility and schema
5. Clean up all resources

This represents the foundational data layer required before deploying Boulder application services in future phases.