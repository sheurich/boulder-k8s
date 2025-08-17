# Agent Guidelines

This document outlines standards and practices that all software development agents must follow.

## Responsibilities

- Read and follow the appropriate phase spec (e.g., SPECp1.md).
- Maintain test coverage for each deliverable.
- Keep `README.md` and usage instructions up-to-date.
- Use declarative Kubernetes YAMLs, and group them into logical files.
- Follow project structure and naming conventions.

## Reference Material

### `./reference/BOULDER.md`

Technical reference guide for Boulder ACME CA development environment setup, architecture, and deployment. Contains service descriptions, configuration examples, and production considerations.

### `./reference/boulder`

Complete Boulder source code repository with Go modules, Docker setup, test configurations, integration tests, and build scripts.

### `./reference/boulder.wiki`

Boulder project wiki with design documents, implementation guides, coding standards, and deployment best practices.

## Tools Available

- macOS host with Docker, Go, and Kubernetes (`kind`) installed.
- Access to Boulder GitHub repository and integration test scripts.

## Boulder-Specific Guidance

### Service Dependencies

Boulder services have strict startup dependencies. Key order:

- Infrastructure first: Redis, PostgreSQL, HSM simulator
- Core services: `boulder-sa` (database layer)
- Validation: `boulder-va`, `remoteva-*` instances
- Certificate services: `boulder-ca`, `boulder-publisher`
- Registration: `boulder-ra` (depends on SA, VA, CA)
- Web frontends: `boulder-wfe2`, `sfe` (depend on RA, SA)

### Testing Validation

- Verify service startup order and health checks
- Test ACME workflow end-to-end before considering deployment complete
- Ensure Boulder's integration tests pass in the Kubernetes environment

## Naming & Structure

### Kubernetes Resources

- Use kebab-case for resource names
- Follow consistent naming patterns

### File Organization

- Group related manifests logically
- Use clear, descriptive filenames
- Keep structure simple and maintainable
