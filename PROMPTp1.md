# Prompt for Agent - Phase 1

You are tasked with implementing Phase 1 of the Boulder-in-Kubernetes project.

## Goal

Containerize and deploy Boulder microservices to a local Kubernetes cluster (kind). Enable Boulder’s integration tests to run in this environment.

## Instructions

- Each Boulder service mode must be deployed in its own pod, using one container image with different commands.
- Use ConfigMaps and Secrets for configuration.
- Use Kubernetes Services for inter-process discovery.
- Set up supporting services (Redis, PostgreSQL, HSM simulator) in-cluster.
- Write clean, reusable YAML manifests.
- Write integration test automation.
- Ensure documentation (`README.md`) stays up to date.
- Follow the project conventions outlined in `AGENTS.md`.

See `SPECp1.md` for full details.
