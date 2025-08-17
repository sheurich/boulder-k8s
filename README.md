# Boulder in Kubernetes

A Kubernetes-native integration environment for Let's Encrypt’s Boulder CA server.

## Overview

This project enables running Boulder and its supporting services (Redis, PostgreSQL, HSM simulator) in Kubernetes, starting with a local Kubernetes-in-Docker (`kind`) setup. Later phases add support for CI/CD and production.

## Quick Start

```bash
make kind-deploy
make run-tests
```

## Project Structure

- `k8s/`: Kubernetes YAML for pods, services, configmaps, secrets
- `tests/`: Integration test automation
- `scripts/`: Utility scripts
- `docs/`: Specifications and notes
