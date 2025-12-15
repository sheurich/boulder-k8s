# Boulder K8s Design

Reference implementation for deploying Boulder to Kubernetes.

## Goals

1. **Production deployment** — Deploy Boulder for internal PKI and WebPKI certificate authorities
2. **Clear reference** — Provide deployment guidance clearer than Boulder's integration test setup
3. **Multi-environment** — Support dev/CI (kind), staging, and production (managed/self-hosted K8s)

## Non-Goals

- Replace Boulder's docker-compose for Boulder development
- Replace Pebble for ACME client testing
- Provide a managed CA service

## Requirements

### Environments

| Environment | Cluster | HSM | CT Logs | Secrets |
|-------------|---------|-----|---------|---------|
| Dev/CI | kind | SoftHSM | Mock | K8s Secrets |
| Staging | Managed/self-hosted | SoftHSM or Luna | Mock | K8s or ESO |
| Production | Managed/self-hosted | Luna | Real | ESO |

### HSM Integration

Boulder signs certificates using keys stored in HSMs via PKCS#11.

**Dev/CI:** SoftHSM accessed via pkcs11-proxy. Boulder-CA loads `libpkcs11-proxy.so`, which connects to a proxy server container backed by SoftHSM with persistent storage.

**Staging/Production:** Thales Luna HSM accessed via NTLS. Boulder-CA loads `libCryptoki2.so` (Luna client), which connects directly to Luna appliances (physical or Cloud HSM).

### Validation Authority Topology

Deploy multi-perspective validation in all environments:
- 1 primary VA
- 3 remote VAs (rva1, rva2, rva3)

CA/Browser Forum requires multi-perspective validation for WebPKI. Running full topology in dev catches integration issues early.

### Certificate Transparency

- Dev/CI/Staging: Mock CT server (`ct-test-srv`)
- Production: Real CT logs (Google, Cloudflare, etc.)

Staging uses mocks to avoid polluting real CT logs with test certificates.

## Architecture Decisions

### Packaging: Helm + Kustomize

**Choice:** Helm for infrastructure dependencies, Kustomize for Boulder services.

**Rationale:** Helm charts exist for Vitess and Redis with production-tested defaults. Kustomize keeps Boulder manifests readable without Go templating. Overlays handle environment differences cleanly.

### Database: Vitess Only

**Choice:** Target Vitess exclusively. Do not support MariaDB/ProxySQL.

**Rationale:** Boulder is deprecating MariaDB/ProxySQL in favor of Vitess. Building for the deprecated path wastes effort.

### Service Discovery: Kubernetes DNS

**Choice:** Use native K8s service DNS. Do not deploy Consul.

**Rationale:** Boulder's service endpoints are config values, not hardcoded to Consul. K8s DNS provides stable names (`boulder-sa.boulder.svc.cluster.local`). One less component to operate.

### Internal PKI: cert-manager

**Choice:** Use cert-manager for Boulder's internal gRPC mTLS certificates.

**Rationale:** cert-manager is the de facto K8s certificate manager. Creates internal CA, issues service certificates, handles renewal automatically.

### Secrets Management

**Choice:** K8s Secrets for dev/CI, External Secrets Operator (ESO) for staging/production.

**Rationale:** K8s Secrets work for local development. ESO integrates with Vault, AWS Secrets Manager, GCP Secret Manager for production secret stores.

### External Access: LoadBalancer

**Choice:** Expose WFE via LoadBalancer service. Provide Ingress passthrough as optional overlay.

**Rationale:** WFE handles TLS termination. LoadBalancer forwards TCP directly—no ingress TLS configuration needed. Works in kind (with metallb/port-forward) and cloud providers natively.

### Network Security: NetworkPolicies

**Choice:** Default-deny with explicit allow rules for Boulder's communication patterns.

**Rationale:** Defense-in-depth alongside Boulder's built-in gRPC mTLS. No service mesh overhead.

### CI Pipeline: GitHub Actions + Scripts

**Choice:** Generic scripts called by GitHub Actions.

**Rationale:** Scripts run anywhere (local, CI, other platforms). GitHub Actions orchestrates but doesn't contain logic.

## Components

### Boulder Services (Deployments)

| Service | Port | Purpose |
|---------|------|---------|
| wfe2 | 4001/4431 | ACME API (HTTP/HTTPS) |
| ra | 9094 | Registration authority |
| sa | 9095 | Storage authority (DB access) |
| ca | 9093 | Certificate authority (HSM access) |
| va | 9092 | Validation authority (primary) |
| rva1/2/3 | 9097-9099 | Remote validation authorities |
| publisher | 9091 | CT log submission |
| nonce-a/b | 9101/9102 | Nonce generation |
| crl-updater | — | CRL generation |
| crl-storer | 9109 | CRL storage |
| observer | 8040 | Health monitoring |
| email-exporter | 9381 | Salesforce integration |
| sfe | 4003 | Self-service frontend |

### Compliance Jobs (CronJobs)

| Job | Schedule | Purpose |
|-----|----------|---------|
| bad-key-revoker | Every 6h | Revoke certificates using compromised keys |
| log-validator | Hourly | Validate Boulder log files |
| cert-checker | Every 4h | Verify issued certificates meet policy |
| crl-checker | Hourly | Validate CRL generation and publication |

### Bootstrap Tasks (Jobs)

| Job | When | Purpose |
|-----|------|---------|
| db-migrate | Pre-deploy | Apply database schema migrations |
| pki-ceremony | First deploy | Generate PKI hierarchy (automated in dev, manual in prod) |

### Test Infrastructure (Dev/CI only)

| Service | Purpose |
|---------|---------|
| challtestsrv | Mock DNS and HTTP challenge responder |
| ct-test-srv | Mock Certificate Transparency log |
| pardot-test-srv | Mock Salesforce for email-exporter |

## Implementation Phases

### Phase 1: MVP (Dev/CI)

Deploy Boulder to kind with automated PKI and mock services. Validate end-to-end certificate issuance.

### Phase 2: Staging/Production

Add Luna HSM overlay, ESO integration, real CT log configuration, production Vitess/Redis configs.

### Phase 3: Operational

Validate compliance CronJobs, add Grafana dashboards, create key ceremony runbooks.

## References

- [Boulder](https://github.com/letsencrypt/boulder) — ACME CA implementation
- [Vitess](https://vitess.io/) — MySQL-compatible database clustering
- [cert-manager](https://cert-manager.io/) — Kubernetes certificate management
- [External Secrets Operator](https://external-secrets.io/) — Kubernetes secrets from external stores
