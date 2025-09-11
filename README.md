# Boulder on Kubernetes (Phase 1)

This project provides a fully automated local development environment for deploying a production-ready MariaDB instance for the Boulder application stack on Kubernetes.

The primary goal of this phase is to establish a foundational data layer. The entire workflow is orchestrated using `just` for simple, repeatable commands.

## Prerequisites

Before you begin, ensure you have the following tools installed on your local machine:

*   [just](https://github.com/casey/just) - Task runner and automation
*   [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) - Local Kubernetes clusters
*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) - Kubernetes CLI
*   [helm](https://helm.sh/docs/intro/install/) - Kubernetes package manager
*   [git](https://git-scm.com/) - Version control (for submodule management)
*   [docker](https://docs.docker.com/get-docker/) - Container runtime (required by kind)

### Quick Installation (macOS)

For macOS users, all prerequisites can be installed using Homebrew:

```sh
# Install all tools using the provided Brewfile
brew bundle

# Verify installations
just --version
kind version
kubectl version --client
helm version
docker version
```

## Getting Started

1.  **Clone the repository:**
    ```sh
    git clone <repository-url>
    cd boulder-k8s
    ```

2.  **Initialize the Boulder submodule:**
    This project uses the official Boulder repository as a submodule to access its SQL migration scripts.
    ```sh
    git submodule update --init --recursive
    ```

## Usage

All tasks are managed via the `justfile` in the root of the repository.

### Create the Environment

The `setup` command creates the local Kubernetes cluster, deploys all dependencies (cert-manager, MariaDB operator), and deploys a primed MariaDB instance.

```sh
just setup
```

### Run Verification Tests

The `test` command is the primary command for a complete, end-to-end verification. It will:
1.  Set up the entire environment by running `just setup`.
2.  Run a Kubernetes Job to verify the database is correctly primed and accessible.
3.  Tear down the entire environment by running `just teardown`.

```sh
just test
```

### Tear Down the Environment

To clean up and delete the `kind` cluster and all associated resources, run:

```sh
just teardown
```

## Project Structure

```
boulder-k8s/
├── boulder/            # Git submodule of the official Boulder repo
├── k8s/                # All Kubernetes manifests and configurations
├── justfile            # Automation recipes for setup, testing, and teardown
└── ...
```
