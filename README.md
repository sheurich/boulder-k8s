# Boulder on Kubernetes (boulder-k8s)

This repository contains a complete set of Infrastructure as Code (IaC) specifications to deploy and operate a publicly-trusted and auditable WebPKI Certification Authority (CA). The primary goal is to run [Let's Encrypt's Boulder](https://github.com/letsencrypt/boulder) CA software on Kubernetes in a manner that is secure, portable, and maintainable across diverse environments (local, cloud, bare metal).

## Project Status

This project is in the early stages of development. The foundational documentation and project structure are in place, but the IaC components are not yet implemented.

## Target Audience

This project is intended for engineers responsible for deploying, maintaining, and operating a production CA. Users are expected to have a strong background in:

-   Public Key Infrastructure (PKI)
-   Kubernetes and Docker
-   Infrastructure as Code (e.g., Helm, Terraform)
-   Site Reliability Engineering (SRE) principles

Contributors are expected to be able to work within the project's AI-assisted development model.

## Guiding Principles

-   **Security First**: The system must be secure by design and default, suitable for a publicly-trusted CA.
-   **Auditability**: The entire system, including this repository's content and history, is an audit artifact. All changes must be clear, justified, and traceable.
-   **Automation**: The full lifecycle of the CA, from deployment to maintenance, will be automated.
-   **Portability**: The IaC will be designed to run on various Kubernetes platforms.

## Testing

This project uses a shell script for end-to-end testing. The test provisions a complete environment, deploys Boulder, and verifies its functionality.

The test requires Docker, `kind`, and `helm` to be installed.

To run the tests:

```sh
./test
```

The test script will:

1.  Build the Boulder Docker image from `boulder.dockerfile`.
2.  Provision a local Kubernetes cluster using `kind`.
3.  Install the Boulder Helm chart.
4.  Run the Helm chart's tests against the deployment.
5.  Uninstall the Helm chart and delete the `kind` cluster upon completion or interruption.

This test should be run before committing any changes to the main branch.

## Getting Started

As an operator or contributor, your first step is to understand the system architecture and development process.

1.  **Architecture**: Read the [**Architecture Document (`docs/architecture.md`)**](./docs/architecture.md) for a high-level overview of the system design and its components.
2.  **Project Tasks**: Review the [**Task List (`TASKS.md`)**](./TASKS.md) to understand the project roadmap and current work items.
3.  **Development Workflow**: This project uses an AI-assisted development model. To contribute, you must understand this process.
    -   Start with the [**Agent Workflow (`docs/agent-workflow.md`)**](./docs/agent-workflow.md) to see how tasks are executed.
    -   Familiarize yourself with the [**Agent Guidelines (`AGENT_GUIDELINES.md`)**](./AGENT_GUIDELINES.md).

## Contributing

Contributions are welcome but must adhere to the project's strict guidelines to maintain auditability and quality. All development work is tracked via GitHub Issues and performed by an AI agent under human supervision. Please see the [Agent Workflow](./docs/agent-workflow.md) for details on how to contribute.
