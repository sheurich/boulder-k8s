# Boulder Kubernetes Reference Implementation

A reference implementation for deploying [Boulder](https://github.com/letsencrypt/boulder) (the ACME CA software) to Kubernetes.

## Overview

This repository provides production-grade Kubernetes manifests for deploying Boulder, supporting:

- **Dev/CI**: Local development with kind clusters
- **Staging**: Production-like testing environments
- **Production**: Full HA deployments with Luna HSM support

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        External Traffic                          │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                       ┌───────▼───────┐
                       │   WFE2        │  ACME API
                       │ (LoadBalancer)│
                       └───────┬───────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
   ┌────▼────┐           ┌─────▼─────┐          ┌─────▼─────┐
   │   RA    │           │    SA     │          │ Publisher │
   │         │           │           │          │           │
   └────┬────┘           └─────┬─────┘          └───────────┘
        │                      │
   ┌────┼────┐            ┌────▼────┐
   │    │    │            │ProxySQL │
┌──▼─┐┌─▼──┐┌▼──┐         │ (pool)  │
│ VA ││ CA ││...│         └────┬────┘
└────┘└──┬─┘└───┘              │
         │                ┌────▼────┐
    ┌────▼────┐           │ MySQL 8 │
    │   HSM   │           │  (DB)   │
    │(SoftHSM │           └─────────┘
    │or Luna) │
    └─────────┘
```

## Quick Start

### Prerequisites

- kubectl
- helm 3.x
- kind (for local development)
- kustomize (or kubectl with kustomize support)

### Local Development

```bash
# Create kind cluster
./scripts/kind-create.sh

# Deploy Boulder
./scripts/deploy.sh dev

# Wait for services
./scripts/wait-ready.sh

# Test certificate issuance
./scripts/test-issuance.sh
```

### Cleanup

```bash
./scripts/teardown.sh
# Or to delete the cluster:
DELETE_CLUSTER=true ./scripts/teardown.sh
```

## Repository Structure

```
boulder-k8s/
├── boulder/                 # Boulder submodule (for reference)
├── helm/                    # Helm values files
│   └── redis/               # Redis values
├── k8s/
│   ├── base/                # Kustomize base manifests
│   │   ├── boulder/         # Boulder service deployments
│   │   ├── bootstrap/       # DB migration, PKI ceremony
│   │   ├── cronjobs/        # Compliance jobs
│   │   ├── network-policies/
│   │   └── observability/   # ServiceMonitors
│   └── overlays/
│       ├── dev/             # Kind + SoftHSM + mocks
│       │   ├── infra/       # MySQL, ProxySQL
│       │   ├── config/      # Boulder configs
│       │   ├── patches/     # Dev-specific patches
│       │   └── ceremony/    # PKI ceremony job
│       ├── staging/         # Production-like
│       └── prod/            # Luna HSM + real CT
├── scripts/                 # Deployment scripts
└── docs/                    # Documentation
```

## Components

### Boulder Services

| Service | Description |
|---------|-------------|
| wfe2 | Web Front End - ACME API |
| ra | Registration Authority |
| sa | Storage Authority |
| ca | Certificate Authority |
| va | Validation Authority |
| rva1-3 | Remote Validation Authorities |
| publisher | CT log publisher |
| nonce-a/b | Nonce services |
| crl-updater | CRL generation |
| crl-storer | CRL storage |
| observer | Health monitoring |
| email-exporter | Salesforce integration |
| sfe | Self-service frontend |

### Compliance CronJobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| bad-key-revoker | Every 6h | Revoke certs with compromised keys |
| log-validator | Every 1h | Validate Boulder logs |
| cert-checker | Every 4h | Verify issued certificates |
| crl-checker | Every 1h | Validate CRLs |

## Configuration

### Environment Overlays

| Aspect | Dev | Staging | Prod |
|--------|-----|---------|------|
| Database | MySQL + ProxySQL | Managed MySQL | Managed MySQL |
| HSM | SoftHSM sidecar | SoftHSM or Luna | Luna |
| CT logs | Mock | Mock | Real |
| Secrets | K8s Secrets | K8s or ESO | ESO |
| Replicas | 1 | 2+ | HA |

### Database Configuration

**Dev/CI (MySQL + ProxySQL):**
- MySQL 8.4 single instance with init scripts
- ProxySQL 2.7.2 for connection pooling
- Boulder services connect to `proxysql:6033`
- Aligned with upstream Boulder's docker-compose architecture

**Production:**
- Managed MySQL (RDS, Cloud SQL) or replicated MySQL
- ProxySQL for connection pooling and read/write splitting
- Optional: Vitess for horizontal scaling at extreme scale

### HSM Configuration

**Dev/CI (SoftHSM):**
- SoftHSM runs as sidecar container in CA pod
- PKI ceremony generates keys using Boulder's `ceremony` tool
- Tokens stored in K8s Secret, restored by init container

**Production (Luna HSM):**
- Mount Luna client library (`libCryptoki2.so`)
- Configure NTLS connection to Luna appliances
- Key ceremony performed manually with HSM admin

## CI/CD

GitHub Actions runs on every PR:

1. **validate** - Lint and validate all manifests
2. **deploy-test** - Deploy to kind, run integration tests
3. **helm-lint** - Validate Helm charts

## Documentation

- [Design](docs/design.md) — Goals, requirements, architecture decisions
- [Boulder](https://github.com/letsencrypt/boulder) — Upstream ACME CA

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Run `./scripts/validate-manifests.sh`
5. Submit a pull request

## License

See [Boulder's license](https://github.com/letsencrypt/boulder/blob/main/LICENSE.txt).
