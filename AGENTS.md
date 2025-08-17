# Agent Guidelines

This document outlines standards and practices that all software development agents must follow.

## Responsibilities

- Read and follow the appropriate phase spec (e.g., SPECp1.md).
- Maintain test coverage for each deliverable.
- Keep `README.md` and usage instructions up-to-date.
- Use declarative Kubernetes YAMLs, and group them into logical files.
- Follow project structure and naming conventions.

## Reference Material

-

## Tools Available

- macOS host with Docker, Go, and Kubernetes (`kind`) installed.
- Access to Boulder GitHub repository and integration test scripts.

## Naming & Structure

- Use `k8s/` for Kubernetes manifests.
- Use `docs/` for specs and prompts.
- Use `tests/` for test automation.
- Use `scripts/` for helper scripts (e.g., setup, teardown).
