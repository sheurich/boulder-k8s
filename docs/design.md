# Boulder K8s Design

Architecturally-accurate reference implementation for deploying Boulder to Kubernetes.

## Goals

1. **Architecturally-accurate reference** — Demonstrate correct Boulder architecture for production environments without production capacity or hardware security
2. **Clear documentation** — Provide deployment guidance clearer than Boulder's integration test setup
3. **Multi-environment** — Support dev/CI (kind), staging, and production (managed/self-hosted K8s)

This project shows how Boulder components connect, communicate, and depend on each other. It uses SoftHSM (not production HSMs) and single-instance databases (not clustered). Organizations deploy to production by replacing dev components with production equivalents while preserving the architecture.

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

**Dev/CI:** SoftHSM as CA pod sidecar. PKI ceremony generates keys in SoftHSM, stores token directory in K8s Secret. CA init container restores tokens; CA loads `libsofthsm2.so` directly. Supports multiple CA replicas (each imports same tokens).

**Staging/Production:** Thales Luna HSM accessed via NTLS. Boulder-CA loads `libCryptoki2.so` (Luna client), which connects directly to Luna appliances (physical or Cloud HSM).

### Validation Authority Topology

Deploy multi-perspective validation in all environments:
- 1 primary VA
- 3 remote VAs (rva1, rva2, rva3)

CA/Browser Forum requires multi-perspective validation for WebPKI. Running full topology in dev catches integration issues early.
Planned: deploy rva1/2/3 as separate deployments/placements to better mirror production multi-perspective validation.

### Certificate Transparency

- Dev/CI/Staging: Mock CT server (`ct-test-srv`)
- Production: Real CT logs (Google, Cloudflare, etc.)

Staging uses mocks to avoid polluting real CT logs with test certificates.

## Boulder Architecture

Boulder implements ACME (RFC 8555) as a microservices architecture. Each service runs as a separate Go binary, communicating via gRPC with mutual TLS.

### Request Flow

```
Client → WFE2 → RA → VA (validation)
                  → CA (issuance)
                  → SA (persistence)
                  → Publisher → CT Logs
```

1. **WFE2** receives ACME requests, validates signatures, forwards to RA
2. **RA** orchestrates the workflow: creates orders, schedules validation, requests issuance
3. **VA** validates domain control via HTTP-01, DNS-01, or TLS-ALPN-01 challenges
4. **CA** signs certificates using HSM-stored keys
5. **SA** persists all state to the database (registrations, orders, certificates)
6. **Publisher** submits certificates to CT logs asynchronously

### Service Roles

| Service | Role |
|---------|------|
| WFE2 | ACME protocol endpoint, signature validation |
| RA | Policy enforcement, workflow orchestration |
| VA | Domain validation, CAA checking |
| CA | Certificate signing via PKCS#11/HSM |
| SA | Database access layer (only service with DB access) |
| Publisher | CT log submission, async certificate storage |
| Nonce | Cryptographic nonce generation for replay protection |
| SFE | Internal admin interface for support operations |

### Background Services

| Service | Role |
|---------|------|
| CRL Updater | Generates Certificate Revocation Lists |
| CRL Storer | Publishes CRLs to storage/CDN |
| Bad Key Revoker | Revokes certificates using compromised keys |
| Log Validator | Validates CT log submissions |
| Email Exporter | Sends contact/case data to Salesforce/Pardot (via WFE2/SFE) |

### Security Model

**Principle:** All internal communication uses mTLS. No plaintext connections between components.

#### Transport Security Matrix

| Connection | Protocol | TLS Required | Client Auth | Notes |
|------------|----------|--------------|-------------|-------|
| Boulder service ↔ service | gRPC | mTLS | Certificate | Internal PKI certs per service |
| Boulder → ProxySQL | MySQL | TLS | Certificate | ProxySQL terminates, re-encrypts to MySQL |
| ProxySQL → MySQL | MySQL | TLS | Certificate | Backend connection encryption |
| Boulder → Redis | Redis | TLS | Certificate | Rate limiter connections |
| Boulder → Vitess | MySQL | TLS | Certificate | vtgate connection |
| WFE2 → Internet | HTTPS | TLS | None | Server-side TLS only |

#### Internal PKI

PKI ceremony generates certificates for all Boulder services. Each service has:
- Unique certificate with service-specific SAN (e.g., `sa.boulder`, `ra.boulder`)
- Mounted at `/certs/ipki/{service}/cert.pem` and `key.pem`
- CA certificate at `/certs/ipki/ca.crt`

Services validate peer certificates against the internal CA and expected SANs (via `hostOverride` in configs).

#### Access Controls

- **HSM isolation**: Only CA accesses HSM; other services cannot sign certificates
- **SA gating**: Only SA accesses database; enforces data access patterns
- **Nonce validation**: Prevents replay attacks in ACME protocol
- **NetworkPolicies**: Default-deny with explicit allow rules

### Observability and Audit

Phase 1 uses a dev-only humanlog pod to ingest logs (stdout) and OTLP traces. Audit log markers use `[AUDIT]` from Boulder’s shared logger; tests assert the presence of audit events during end-to-end issuance.

Staging/production observability is TBD; required capabilities include:
- Append-only or immutable log storage
- Retention and export controls
- Queryable audit trail for issuance events
- Secure transport (mTLS/OTLP)
- Access controls and tenant isolation

## Architecture Decisions

### Packaging: Helm + Kustomize

**Choice:** Helm for infrastructure dependencies, Kustomize for Boulder services.

**Rationale:** Helm charts exist for Vitess and Redis with production-tested defaults. Kustomize keeps Boulder manifests readable without Go templating. Overlays handle environment differences cleanly.

### Database Architecture

Two database architectures supported as first-class options:

Upstream Boulder is transitioning from ProxySQL + MariaDB (MariaDB-specific SQL) to Vitess + MySQL 8. This repo supports both during the migration; the ProxySQL overlay here runs on MySQL 8.4.

**MySQL + ProxySQL (default)**
- Overlay: `k8s/overlays/dev`
- Connection: `proxysql:6033`
- Use when: Starting fresh, running typical volumes (<10M certs/month), or no Vitess expertise on team

Aligns with upstream Boulder's docker-compose architecture. ProxySQL provides connection pooling, query routing, and timeout management. MySQL 8.4 ensures compatibility with Boulder's SQL requirements.

**Vitess**
- Overlay: `k8s/overlays/dev-vitess`
- Connection: `vitess:3306`
- Use when: Extreme scale (10M+ certs/month), existing Vitess infrastructure, or need horizontal sharding

Vitess provides MySQL-compatible interface with built-in sharding. Let's Encrypt uses Vitess in production. Requires Vitess operational expertise.

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

These services simulate the external Internet and third-party services for end-to-end testing. Production uses real equivalents.

| Service | Simulates | Purpose |
|---------|-----------|---------|
| challtestsrv | Public Internet | Answers DNS queries, hosts HTTP-01/TLS-ALPN-01 challenge responses |
| ct-test-srv | CT Logs (Google, Cloudflare) | Accepts precertificate submissions |
| pardot-test-srv | Salesforce API | Mocks CRM integration for email-exporter |
| s3-test-srv | Amazon S3 | Mocks object storage for CRL/backup |
| aia-test-srv (planned) | AIA endpoints | Serves issuer certificates for chain validation |

**challtestsrv** is the most critical—it acts as the "Internet" for validation, providing both a fake DNS authority and challenge responder that the VA queries during domain validation.

### Infrastructure Dependencies

| Component | Role | Dev/CI | Production |
|-----------|------|--------|------------|
| Database | Relational storage (registrations, orders, certs) | MySQL+ProxySQL or Vitess | Managed MySQL cluster or Vitess |
| Redis | Rate limiting and short-lived operational state | Single instance | Clustered |
| HSM | CA private key storage | SoftHSM sidecar | Thales Luna |
| DNS Resolver (VA) | Recursive resolver for VA validation | challtestsrv DNS (dev) + CoreDNS for cluster services | Unbound |
| Audit logging/tracing | Log/trace ingestion and review | humanlog (dev-only pod) | TBD (see requirements) |
| Jaeger | Distributed tracing | Planned (Phase 2+) | Planned (Phase 2+) |
| Prometheus | Metrics scraping | ServiceMonitors | ServiceMonitors |

**MySQL + ProxySQL** follows upstream Boulder's docker-compose architecture. ProxySQL handles connection pooling, query timeout management, and enables future read/write splitting with replicas. **Vitess** follows Let's Encrypt's production architecture with horizontal sharding for extreme scale.

**Redis** handles high-frequency operations: rate limit counters, nonce validation, and short-term state. Dev uses separate instances to simulate availability zone separation.

## Implementation Phases

### Phase 1: MVP (Dev/CI)

Deploy Boulder to kind with automated PKI and mock services. Add dev-only humanlog for logs/traces and validate end-to-end issuance with audit log assertions.

### Phase 2: Staging/Production

Add Luna HSM overlay, ESO integration, real CT log configuration, production Vitess/Redis configs, and select a staging/production audit logging/tracing stack.

### Phase 3: Operational

Validate compliance CronJobs, add Grafana dashboards, create key ceremony runbooks.

## References

- [Boulder](https://github.com/letsencrypt/boulder) — ACME CA implementation
- [Vitess](https://vitess.io/) — MySQL-compatible database clustering
- [cert-manager](https://cert-manager.io/) — Kubernetes certificate management
- [External Secrets Operator](https://external-secrets.io/) — Kubernetes secrets from external stores
