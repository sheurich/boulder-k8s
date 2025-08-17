# Phase 2 Spec: Multi-Environment & CI-Compatible Deployment

## Objective

Extend the Kubernetes-based Boulder integration environment to support deployment in:

- Local development (kind)
- CI/CD environments (GitHub Actions, etc.)
- Production-like environments (e.g., GKE)

## Requirements

### Environment-Specific Configuration

- Use Kustomize overlays or Helm charts to separate configurations for:
  - Development
  - CI
  - Production

### Network HSM Integration

- Deploy SoftHSM2 with pkcs11-proxy using `vegardit/softhsm2-pkcs11-proxy` Docker image
- Configure Boulder CA services to use `libpkcs11-proxy.so` for network PKCS#11 access
- Implement TLS-PSK authentication between Boulder CA and HSM service
- Support multiple HSM instances for high availability
- Replace Phase 1's file-based certificate approach with secure network HSM operations

### Secrets & Credential Rotation

- Integrate with cloud-native secrets management (e.g., GCP Secret Manager for prod).
- Implement secret rotation strategies for both traditional secrets and HSM credentials.

### CI/CD Pipeline Integration

- Add GitHub Actions workflows to:
  - Build and push container images
  - Deploy to `kind` for integration testing
  - Tear down environment after tests complete

### Testing & Monitoring

- Run Boulder’s full integration test suite on every PR.
- Optional: Add monitoring stack (Prometheus + Grafana) for prod/staging.

## Deliverables

- `ci/` folder with GitHub Actions workflow YAMLs.
- Extended README for CI and production use.
- Environment-specific overlays in `overlays/` or Helm `values.yaml`.
