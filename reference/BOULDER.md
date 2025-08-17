# Boulder Development Environment Guide

## 1. Executive Summary

Boulder is a production-grade, open-source Automated Certificate Management Environment (ACME) Certificate Authority (CA) developed by Let's Encrypt. It is designed to handle the issuance, renewal, and revocation of a massive volume of X.509 certificates for Transport Layer Security (TLS). This document provides a comprehensive technical reference for system administrators, developers, and security engineers responsible for deploying, operating, and maintaining a Boulder instance, with particular focus on the development environment setup.

## 2. Running the Development Environment

The Boulder development environment is designed to be run using Docker Compose and provides a complete, integrated testing environment that closely mirrors production deployments.

### Quick Start

To build and run the development environment:

```bash
docker compose build boulder && ./t.sh
```

This command performs the following operations:

1. **`docker compose build boulder`**: Builds the Boulder Docker images using the [`boulder-tools`](boulder/test/boulder-tools/) container which includes all necessary dependencies (Go compiler, development tools, etc.)
2. **`./t.sh`**: Starts the integration test suite which:
   - Generates test certificates via the `bsetup` service
   - Starts all Boulder services in dependency order using [`startservers.py`](boulder/test/startservers.py)
   - Runs comprehensive integration tests
   - Provides a fully functional ACME environment for development and testing

The development environment exposes:

- **ACME API (WFE2)**: `http://localhost:4001`
- **SFE (Self-Service Portal)**: `http://localhost:4003`

## 3. Architecture Overview

Boulder employs a microservice-based architecture, with distinct services communicating via gRPC secured with mutual TLS (mTLS). The system is designed for high availability, scalability, and security.

### High-Level Design

- **Monolithic Binary, Distributed Services:** Core logic is compiled into a single `boulder` binary, which is launched with different sub-commands to run each specific service (e.g., `boulder-ra`, `boulder-ca`).
- **Service Discovery:** Services register with and discover each other using Consul for service registration and DNS-based SRV record lookups.
- **Data Storage:** MariaDB is the primary database for storing account information, certificate data, and issuance records. Redis is used for rate limiting with two sharded instances for distributed rate limiting.
- **PKI Management:** Boulder uses two distinct PKI hierarchies: the public certificate hierarchy managed by the `ceremony` tool for issuing certificates, and an internal PKI for service-to-service mTLS authentication.
- **Asynchronous Workflows:** Many operations, such as certificate issuance and revocation, are handled asynchronously through a series of state transitions managed by different services.

### Docker Networking Setup

The development environment uses three distinct Docker networks as defined in [`docker-compose.yml`](boulder/docker-compose.yml):

| Network          | Subnet              | Purpose                                                                                                                                                                             |
| ---------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`bouldernet`** | `10.77.77.0/24`     | Internal data-center network for Boulder services and infrastructure (Consul, MariaDB, Redis). Services use static IPs in the lower half of the range.                              |
| **`publicnet`**  | `64.112.117.0/25`   | Simulates the public internet using real Let's Encrypt-controlled IP space. Used by `challtestsrv` for HTTP-01 challenge responses on `64.112.117.122:80` and `64.112.117.122:443`. |
| **`publicnet2`** | `64.112.117.128/25` | Secondary public network for TLS-ALPN-01 challenges on `64.112.117.134:443` and additional test scenarios that require separate HTTP servers.                                       |

This networking setup allows integration tests to validate challenge responses from what appears to be external internet addresses while maintaining isolation.

## 4. Component Architecture

### Tier 1 - Boulder Internal Components

Core microservices architected and maintained by Let's Encrypt as the foundational ACME protocol implementation:

- **CA (Certificate Authority)**: Signs certificates, generates CRLs, and is the only component with access to private keys for certificate signing
- **RA (Registration Authority)**: Manages account creation, validation challenges, and orchestrates the entire certificate issuance workflow
- **SA (Storage Authority)**: Database abstraction layer handling all interactions with MariaDB for storing accounts, orders, authorizations, and certificates
- **VA (Validation Authority)**: Performs domain control validation challenges (HTTP-01, DNS-01, TLS-ALPN-01) with Multi-Perspective Issuance Corroboration
- **Publisher**: Publishes issued certificates and precertificates to Certificate Transparency logs for CT compliance
- **WFE2 (Web Front End v2)**: Public-facing ACME API endpoint that receives client requests, validates them, and forwards to appropriate backend services
- **Nonce Service**: Provides single-use nonces for ACME replay attack prevention with geographic distribution across datacenters
- **Remote VAs**: Additional VA instances (remoteva-a, remoteva-b, remoteva-c) performing validation from different network perspectives for MPIC compliance
- **Boulder Observer**: Monitoring service that probes Boulder services to ensure health and operational status
- **CRL Storer**: Manages storage and distribution of Certificate Revocation Lists with sharding support
- **CRL Updater**: Generates and updates Certificate Revocation Lists based on revoked certificates
- **SFE (Self-service Front End)**: Web portal for self-service account management and certificate operations
- **Bad Key Revoker**: Monitors for compromised or weak private keys and automatically revokes associated certificates
- **Cert Checker**: Validates issued certificates for compliance and correctness
- **Email Exporter**: Exports email-related metrics and handles email notifications for administrative purposes
- **Log Validator**: Validates Certificate Transparency log submissions and monitors CT log health
- **Reversed Hostname Checker**: Validates reverse DNS lookups for certificate issuance policies
- **Admin**: Administrative interface for privileged operations and system management
- **CRL Checker**: Validates CRL generation and distribution for compliance
- **Ceremony**: Tool for managing secure key generation and certificate signing operations with HSM integration

### Tier 2 - Boulder Dependencies

Critical third-party infrastructure services and libraries essential for Boulder's operational functionality:

- **MariaDB**: Primary relational database for persistent storage of all Boulder data
- **Redis**: Caching layer used for distributed rate limiting with sharded instances
- **ProxySQL**: Database proxy providing connection pooling, load balancing, and resilience between Boulder services and MariaDB
- **Internal DNS Infrastructure**: Service discovery system (Consul in Docker Compose, Kubernetes DNS in K8s deployment)
- **VA DNS Infrastructure**: DNSSEC-validating Internet resolver for domain validation challenges
- **Internal PKI Infrastructure**: Certificate generation system for TLS/mTLS between Boulder services
- **PKCS#11 Implementation**: SoftHSM for development, hardware HSM for production key storage
- **WebPKI Trust Store**: Generated certificates via Boulder ceremony tool for CA operations
- **Consul**: Service discovery and health checking in Docker Compose environment (replaced by Kubernetes services in K8s)
- **Jaeger**: Distributed tracing system for monitoring requests across microservice architecture

### Tier 3 - Boulder Integration Test Components

Specialized testing services and mock implementations required exclusively for Boulder's integration test suite:

- **chall-test-srv**: Challenge test server responding to HTTP-01, DNS-01, and TLS-ALPN-01 challenges for integration testing
- **ct-test-srv**: Mock Certificate Transparency log server for testing certificate submission and SCT retrieval
- **pardot-test-srv**: Mock Salesforce Pardot API server for testing email marketing integration
- **load-generator**: Performance testing tool generating load against Boulder services
- **health-checker**: Service health validation tool for integration test environments
- **aia-test-srv**: Authority Information Access test server serving intermediate certificates
- **zendesk-test-srv**: Mock Zendesk API server for testing support ticket integration
- **s3-test-srv**: S3-compatible object storage test server for CRL distribution testing
- **boulder-tools**: Development and testing utilities container with Go compiler and dependencies
- **chall-test-srv-client**: Client library for interacting with challenge test server
- **list-features**: Tool for listing enabled Boulder feature flags
- **inmem**: In-memory implementations of Boulder services for lightweight testing
- **integration**: Integration test suite runner and test case implementations
- **bsetup**: Certificate generation service creating test PKI hierarchies during environment setup

## 5. Core Services and Dependencies

For a functional Boulder deployment, the following core services and supporting infrastructure are required.

### Core Boulder Services

These are the essential Boulder services required for basic ACME functionality.

| Service                         | Description                                                                                                                                                                                                                                                                      |
| :------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Web Front End (WFE2)**        | The public-facing ACME API endpoint. It receives all client requests, validates them, and forwards them to the appropriate backend service. Handles nonce management and rate limiting.                                                                                          |
| **Registration Authority (RA)** | Manages account creation, validation challenges, and issuance policies. It determines whether a client is authorized to be issued a certificate. Orchestrates the entire certificate issuance workflow.                                                                          |
| **Certificate Authority (CA)**  | The heart of the system. It signs certificate requests, generates OCSP responses, and produces Certificate Revocation Lists (CRLs). It is the only component with access to the private keys used for signing certificates.                                                      |
| **Validation Authority (VA)**   | Performs the domain control validation challenges (e.g., HTTP-01, DNS-01, TLS-ALPN-01) to verify that a client controls the identifiers in a certificate request. Implements Multi-Perspective Issuance Corroboration (MPIC).                                                    |
| **Storage Authority (SA)**      | The database abstraction layer. It handles all interactions with MariaDB, managing the storage and retrieval of accounts, orders, authorizations, and certificates.                                                                                                              |
| **Nonce Service**               | Provides single-use nonces that ACME clients must include in their requests to prevent replay attacks. Multiple instances run across datacenters (`nonce-service-taro-1/2`, `nonce-service-zinc-1/2`) for high availability and geographic distribution.                         |
| **Publisher**                   | Publishes issued certificates and precertificates to Certificate Transparency (CT) logs. Required for CT compliance in production deployments.                                                                                                                                   |
| **Remote VAs**                  | Additional VA instances (`remoteva-a`, `remoteva-b`, `remoteva-c`) that perform validation from different network perspectives to implement Multi-Perspective Issuance Corroboration (MPIC). Required for security against single-point-of-failure attacks on domain validation. |
| **CRL Storer**                  | Manages the storage and distribution of Certificate Revocation Lists (CRLs). Handles CRL sharding and ensures CRL availability across multiple distribution points.                                                                                                              |
| **Bad Key Revoker**             | Monitors for compromised or weak private keys and automatically revokes certificates that were issued for those keys. Essential for maintaining the security and integrity of the certificate ecosystem.                                                                         |
| **Log Validator**               | Validates Certificate Transparency (CT) log submissions and ensures that submitted certificates appear correctly in CT logs. Monitors CT log health and consistency.                                                                                                             |
| **Email Exporter**              | Exports email-related metrics and handles email notifications for administrative and operational purposes. Provides integration with external monitoring and alerting systems.                                                                                                   |

### Supporting Infrastructure

These are the external dependencies required for a Boulder deployment.

| Component           | Description                                                                                                                  | Configuration Notes                                                   |
| :------------------ | :--------------------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------- |
| **MariaDB**         | The primary relational database for persistent storage.                                                                      | The SA service connects to this via ProxySQL.                         |
| **ProxySQL**        | Database proxy that sits between Boulder services and MariaDB, providing connection pooling, load balancing, and resilience. | All database connections route through this proxy.                    |
| **Redis (Sharded)** | Two Redis instances (`bredis_1`, `bredis_2`) used for distributed rate limiting with sharded data across multiple instances. | Used by WFE2 and RA services for TAT-based rate limiting.             |
| **Consul**          | Used for service discovery, health checking, and DNS resolution for Boulder services.                                        | All Boulder services register with Consul and use SRV record lookups. |
| **Jaeger**          | Distributed tracing system for monitoring and debugging requests across the microservice architecture.                       | Provides observability for request flows.                             |
| **PKIMetal**        | External certificate and CRL linting service that validates compliance against industry standards.                           | Used in testing environments for compliance validation.               |

#### Certificate Setup Service

| Service      | Description                                                                                                                                                                                                                                                                                                                 |
| :----------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`bsetup`** | A setup service that generates test certificates by running [`test/certs/generate.sh`](boulder/test/certs/generate.sh). This creates both the Web PKI hierarchy (for certificate issuance) and the internal PKI hierarchy (for service-to-service mTLS). Only runs during environment setup via `docker compose up bsetup`. |

### Test Environment Services

The development environment includes additional services specifically for testing and integration validation:

| Service                | Port        | Description                                                                                                                                                                                                                                                                                                                                     |
| :--------------------- | :---------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`chall-test-srv`**   | 8055 (mgmt) | Challenge test server that responds to HTTP-01, DNS-01, and TLS-ALPN-01 challenges during Boulder's integration testing. This service simulates domain ownership scenarios and provides controlled responses for validation testing, allowing comprehensive testing of Boulder's domain validation logic without requiring real domain control. |
| **`aia-test-srv`**     | 4502        | Authority Information Access test server that serves intermediate certificates and OCSP responder URLs.                                                                                                                                                                                                                                         |
| **`ct-test-srv`**      | 4600        | Certificate Transparency test server that simulates CT logs for testing certificate submission and SCT retrieval.                                                                                                                                                                                                                               |
| **`s3-test-srv`**      | 4501        | S3-compatible object storage test server used for CRL distribution testing.                                                                                                                                                                                                                                                                     |
| **`akamai-test-srv`**  | 6789        | Mock Akamai CDN purging service for testing cache invalidation functionality.                                                                                                                                                                                                                                                                   |
| **`pardot-test-srv`**  | 9601-9602   | Mock Salesforce Pardot API server for testing email marketing integration.                                                                                                                                                                                                                                                                      |
| **`zendesk-test-srv`** | 9701        | Mock Zendesk API server for testing support ticket integration.                                                                                                                                                                                                                                                                                 |

## 6. Service Orchestration

The Boulder development environment uses a sophisticated service orchestration system to ensure services start in the correct dependency order.

### Service Startup Management

The [`test/startservers.py`](boulder/test/startservers.py) script manages the startup of all Boulder services. It defines services in a `SERVICES` tuple, where each service includes:

- **Name**: Service identifier
- **Debug Port**: HTTP port for debugging and metrics
- **gRPC Port**: Port for gRPC service communication (if applicable)
- **Host Override**: TLS hostname override for mTLS connections
- **Command**: Full command line to start the service
- **Dependencies**: List of services that must be running before this service starts

### Dependency-Based Startup Order

The `_service_toposort()` function in [`startservers.py`](boulder/test/startservers.py) performs a topological sort of services based on their dependencies, ensuring that:

1. No service starts until all its dependencies are healthy
2. Services are started in dependency order to prevent connection failures
3. Circular dependencies are detected and reported as errors

### Service Dependencies and Commands

| Service                       | Debug Port | gRPC Port | Dependencies                                                                                                                                | Command                                                                                                      |
| :---------------------------- | :--------- | :-------- | :------------------------------------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------- |
| **remoteva-a**                | 8011       | 9397      | None                                                                                                                                        | `./bin/boulder remoteva --config test/config/remoteva-a.json --addr :9397 --debug-addr :8011`                |
| **remoteva-b**                | 8012       | 9498      | None                                                                                                                                        | `./bin/boulder remoteva --config test/config/remoteva-b.json --addr :9498 --debug-addr :8012`                |
| **remoteva-c**                | 8023       | 9499      | None                                                                                                                                        | `./bin/boulder remoteva --config test/config/remoteva-c.json --addr :9499 --debug-addr :8023`                |
| **boulder-sa-1**              | 8003       | 9395      | None                                                                                                                                        | `./bin/boulder boulder-sa --config test/config/sa.json --addr :9395 --debug-addr :8003`                      |
| **boulder-sa-2**              | 8103       | 9495      | None                                                                                                                                        | `./bin/boulder boulder-sa --config test/config/sa.json --addr :9495 --debug-addr :8103`                      |
| **boulder-publisher-1**       | 8009       | 9391      | None                                                                                                                                        | `./bin/boulder boulder-publisher --config test/config/publisher.json --addr :9391 --debug-addr :8009`        |
| **boulder-publisher-2**       | 8109       | 9491      | None                                                                                                                                        | `./bin/boulder boulder-publisher --config test/config/publisher.json --addr :9491 --debug-addr :8109`        |
| **boulder-va-1**              | 8004       | 9392      | remoteva-a, remoteva-b                                                                                                                      | `./bin/boulder boulder-va --config test/config/va.json --addr :9392 --debug-addr :8004`                      |
| **boulder-va-2**              | 8104       | 9492      | remoteva-a, remoteva-b                                                                                                                      | `./bin/boulder boulder-va --config test/config/va.json --addr :9492 --debug-addr :8104`                      |
| **boulder-ra-sct-provider-1** | 8118       | 9594      | boulder-publisher-1, boulder-publisher-2                                                                                                    | `./bin/boulder boulder-ra --config test/config/ra.json --addr :9594 --debug-addr :8118`                      |
| **boulder-ra-sct-provider-2** | 8119       | 9694      | boulder-publisher-1, boulder-publisher-2                                                                                                    | `./bin/boulder boulder-ra --config test/config/ra.json --addr :9694 --debug-addr :8119`                      |
| **boulder-ca-1**              | 8001       | 9393      | boulder-sa-1, boulder-sa-2, boulder-ra-sct-provider-1, boulder-ra-sct-provider-2                                                            | `./bin/boulder boulder-ca --config test/config/ca.json --addr :9393 --debug-addr :8001`                      |
| **boulder-ca-2**              | 8101       | 9493      | boulder-sa-1, boulder-sa-2, boulder-ra-sct-provider-1, boulder-ra-sct-provider-2                                                            | `./bin/boulder boulder-ca --config test/config/ca.json --addr :9493 --debug-addr :8101`                      |
| **boulder-ra-1**              | 8002       | 9394      | boulder-sa-1, boulder-sa-2, boulder-ca-1, boulder-ca-2, boulder-va-1, boulder-va-2, akamai-purger, boulder-publisher-1, boulder-publisher-2 | `./bin/boulder boulder-ra --config test/config/ra.json --addr :9394 --debug-addr :8002`                      |
| **boulder-ra-2**              | 8102       | 9494      | boulder-sa-1, boulder-sa-2, boulder-ca-1, boulder-ca-2, boulder-va-1, boulder-va-2, akamai-purger, boulder-publisher-1, boulder-publisher-2 | `./bin/boulder boulder-ra --config test/config/ra.json --addr :9494 --debug-addr :8102`                      |
| **nonce-service-taro-1**      | 8021       | 9501      | None                                                                                                                                        | `./bin/boulder nonce-service --config test/config/nonce-service-taro.json --addr :9501 --debug-addr :8021`   |
| **nonce-service-taro-2**      | 8121       | 9601      | None                                                                                                                                        | `./bin/boulder nonce-service --config test/config/nonce-service-taro.json --addr :9601 --debug-addr :8121`   |
| **nonce-service-zinc-1**      | 8022       | 9502      | None                                                                                                                                        | `./bin/boulder nonce-service --config test/config/nonce-service-zinc.json --addr :9502 --debug-addr :8022`   |
| **nonce-service-zinc-2**      | 8122       | 9602      | None                                                                                                                                        | `./bin/boulder nonce-service --config test/config/nonce-service-zinc.json --addr :9602 --debug-addr :8122`   |
| **crl-storer-1**              | 8024       | 9503      | boulder-sa-1, boulder-sa-2                                                                                                                  | `./bin/boulder crl-storer --config test/config/crl-storer.json --addr :9503 --debug-addr :8024`              |
| **crl-storer-2**              | 8124       | 9603      | boulder-sa-1, boulder-sa-2                                                                                                                  | `./bin/boulder crl-storer --config test/config/crl-storer.json --addr :9603 --debug-addr :8124`              |
| **bad-key-revoker-1**         | 8025       | 9504      | boulder-sa-1, boulder-sa-2                                                                                                                  | `./bin/boulder bad-key-revoker --config test/config/bad-key-revoker.json --addr :9504 --debug-addr :8025`    |
| **log-validator-1**           | 8026       | 9505      | boulder-sa-1, boulder-sa-2                                                                                                                  | `./bin/boulder log-validator --config test/config/log-validator.json --addr :9505 --debug-addr :8026`        |
| **email-exporter-1**          | 8027       | 9506      | boulder-sa-1, boulder-sa-2                                                                                                                  | `./bin/boulder email-exporter --config test/config/email-exporter.json --addr :9506 --debug-addr :8027`      |
| **boulder-wfe2**              | 8013       | N/A       | boulder-ra-1, boulder-ra-2, boulder-sa-1, boulder-sa-2, nonce-service-taro-1, nonce-service-taro-2, nonce-service-zinc-1, email-exporter-1  | `./bin/boulder boulder-wfe2 --config test/config/wfe2.json --addr :4001 --tls-addr :4431 --debug-addr :8013` |
| **sfe**                       | 8015       | N/A       | boulder-ra-1, boulder-ra-2, boulder-sa-1, boulder-sa-2, zendesk-test-srv                                                                    | `./bin/boulder sfe --config test/config/sfe.json --debug-addr :8015`                                         |

### SCT Provider Services

The **`boulder-ra-sct-provider`** services are specialized Registration Authority instances that handle Signed Certificate Timestamp (SCT) operations. These services exist to resolve a circular dependency in Boulder's development environment:

- The CA service needs SCTs from CT logs to include in issued certificates
- CT logs require valid certificates to be submitted
- In production, this is resolved through external CT log infrastructure
- In the development environment, these specialized RA instances act as SCT providers, breaking the circular dependency

The SCT provider services run the same RA code but with specialized configuration that focuses on providing SCT services to the CA components without creating dependency loops.

### Nonce Service IP Binding and Sharding

Boulder's nonce services use IP-based sharding to distribute nonce generation and validation across multiple service instances. The services are configured with specific IP bindings that enable consistent prefix-based nonce routing:

- **`nonce-service-taro`**: Handles nonces with specific prefix patterns calculated from client IP addresses
- **`nonce-service-zinc`**: Handles nonces with different prefix patterns for load distribution

This sharding approach ensures that:

1. Nonces are consistently routed to the correct service instance for validation
2. Load is distributed across multiple nonce service instances
3. Geographic distribution is supported (taro/zinc representing different datacenter locations)
4. High availability is maintained through redundant service instances

The IP binding configuration uses the client's source IP address to calculate which nonce service should handle the request, ensuring that nonce redemption requests are routed to the same service that originally issued the nonce.

## 7. Component Configuration

Boulder services are configured primarily through JSON configuration files. Each service requires a comprehensive configuration that includes TLS settings, service discovery, and service-specific parameters.

**Note**: The configuration examples in this section are simplified excerpts from Boulder's development environment. Production deployments require additional configuration sections for security policies, operational monitoring, compliance settings, and environment-specific parameters.

### Configuration File Structure

All configuration files follow a common pattern with these key sections:

- **Service-specific configuration**: Core settings for the service
- **TLS configuration**: mTLS certificates and CA for service-to-service communication
- **Service discovery**: gRPC client configuration for dependent services
- **Logging configuration**: Syslog and stdout logging levels

### Registration Authority (RA) Configuration

The RA service coordinates certificate issuance and manages validation workflows. Key configuration from [`test/config/ra.json`](boulder/test/config/ra.json):

```json
{
  "ra": {
    "limiter": {
      "redis": {
        "username": "boulder-wfe",
        "passwordFile": "test/secrets/wfe_ratelimits_redis_password",
        "lookups": [
          {
            "Service": "redisratelimits",
            "Domain": "service.consul"
          }
        ],
        "lookupDNSAuthority": "consul.service.consul"
      },
      "Defaults": "test/config/wfe2-ratelimit-defaults.yml",
      "Overrides": "test/config/wfe2-ratelimit-overrides.yml"
    },
    "tls": {
      "caCertFile": "test/certs/ipki/minica.pem",
      "certFile": "test/certs/ipki/ra.boulder/cert.pem",
      "keyFile": "test/certs/ipki/ra.boulder/key.pem"
    },
    "vaService": {
      "dnsAuthority": "consul.service.consul",
      "srvLookup": {
        "service": "va",
        "domain": "service.consul"
      },
      "hostOverride": "va.boulder"
    },
    "validationProfiles": {
      "legacy": {
        "pendingAuthzLifetime": "168h",
        "validAuthzLifetime": "720h",
        "orderLifetime": "168h",
        "maxNames": 100,
        "identifierTypes": ["dns"]
      }
    }
  }
}
```

**Key RA Configuration Elements:**

- **`limiter`**: Redis-based distributed rate limiting configuration
- **`validationProfiles`**: Different validation policies (legacy, modern, shortlived)
- **`vaService`**: Connection to Validation Authority services via Consul SRV lookup
- **`issuerCerts`**: List of intermediate certificate files for different key types (RSA/ECDSA)

### Certificate Authority (CA) Configuration

The CA service handles certificate signing and CRL generation. Key configuration from [`test/config/ca.json`](boulder/test/config/ca.json):

```json
{
  "ca": {
    "issuance": {
      "certProfiles": {
        "legacy": {
          "allowMustStaple": false,
          "omitCommonName": false,
          "maxValidityPeriod": "7776000s",
          "maxValidityBackdate": "1h5m"
        }
      },
      "issuers": [
        {
          "active": true,
          "crlShards": 10,
          "issuerURL": "http://ca.example.org:4502/int-ecdsa-a",
          "crlURLBase": "http://ca.example.org:4501/lets-encrypt-crls/43104258997432926/",
          "location": {
            "configFile": "test/certs/webpki/int-ecdsa-a.pkcs11.json",
            "certFile": "test/certs/webpki/int-ecdsa-a.cert.pem",
            "numSessions": 2
          }
        }
      ]
    },
    "sctService": {
      "dnsAuthority": "consul.service.consul",
      "srvLookup": {
        "service": "ra-sct-provider",
        "domain": "service.consul"
      },
      "hostOverride": "ra.boulder"
    }
  }
}
```

**Key CA Configuration Elements:**

- **`certProfiles`**: Different certificate profiles with varying validation periods and extensions
- **`issuers`**: Configuration for multiple intermediate CA certificates (RSA/ECDSA)
- **`crlShards`**: Number of CRL shards for distributing revoked certificates
- **`location`**: PKCS#11 configuration for HSM integration in production

### Validation Authority (VA) Configuration

The VA service performs domain validation challenges. Key configuration from [`test/config/va.json`](boulder/test/config/va.json):

```json
{
  "va": {
    "dnsProvider": {
      "dnsAuthority": "consul.service.consul",
      "srvLookup": {
        "service": "doh",
        "domain": "service.consul"
      }
    },
    "remoteVAs": [
      {
        "serverAddress": "rva1.service.consul:9397",
        "timeout": "15s",
        "hostOverride": "rva1.boulder",
        "perspective": "dadaist",
        "rir": "ARIN"
      }
    ],
    "features": {
      "DOH": true
    }
  }
}
```

**Key VA Configuration Elements:**

- **`dnsProvider`**: DNS-over-HTTPS provider for secure DNS resolution
- **`remoteVAs`**: Multiple remote validation perspectives for MPIC compliance
- **`perspective`** and **`rir`**: Geographic and network diversity identifiers

### Storage Authority (SA) Configuration

The SA service manages database interactions. Key configuration from [`test/config/sa.json`](boulder/test/config/sa.json):

```json
{
  "sa": {
    "db": {
      "dbConnectFile": "test/secrets/sa_dburl",
      "maxOpenConns": 100
    },
    "readOnlyDB": {
      "dbConnectFile": "test/secrets/sa_ro_dburl",
      "maxOpenConns": 100
    },
    "incidentsDB": {
      "dbConnectFile": "test/secrets/incidents_dburl",
      "maxOpenConns": 100
    },
    "features": {
      "MultipleCertificateProfiles": true,
      "InsertAuthzsIndividually": true
    }
  }
}
```

**Key SA Configuration Elements:**

- **`db`**: Primary database connection for read-write operations
- **`readOnlyDB`**: Separate read-only database connection for query load balancing
- **`incidentsDB`**: Separate database for incident tracking and security events

### Web Front End (WFE2) Configuration

The WFE2 service provides the public ACME API. Key configuration from [`test/config/wfe2.json`](boulder/test/config/wfe2.json):

```json
{
  "wfe": {
    "listenAddress": "0.0.0.0:4001",
    "getNonceService": {
      "dnsAuthority": "consul.service.consul",
      "srvLookup": {
        "service": "nonce-taro",
        "domain": "service.consul"
      }
    },
    "redeemNonceService": {
      "srvLookups": [
        {
          "service": "nonce-taro",
          "domain": "service.consul"
        },
        {
          "service": "nonce-zinc",
          "domain": "service.consul"
        }
      ]
    },
    "chains": [
      [
        "test/certs/webpki/int-rsa-a.cert.pem",
        "test/certs/webpki/root-rsa.cert.pem"
      ]
    ]
  }
}
```

**Key WFE2 Configuration Elements:**

- **`getNonceService`**: Primary nonce service for issuing new nonces
- **`redeemNonceService`**: Multiple nonce services for redeeming nonces (cross-datacenter support)
- **`chains`**: Certificate chain configurations for different key types
- **`certProfiles`**: Available certificate profiles exposed to clients

## 8. Service Discovery and Communication

Boulder services use Consul for service discovery and communicate via gRPC with mTLS authentication. The development environment uses DNS-based service discovery with SRV record lookups.

### Service Registration Pattern

All services register with Consul and can be discovered via SRV records:

```
_<service>._tcp.service.consul
```

For example, the RA service can be found at:

```
_ra._tcp.service.consul
```

### Client Service Dependencies

| Client Service | Server Dependency | Configuration Block                     | Purpose                                   |
| :------------- | :---------------- | :-------------------------------------- | :---------------------------------------- |
| WFE2           | RA                | `raService`                             | Certificate orders and account operations |
| WFE2           | SA                | `saService`                             | Read-only database queries                |
| WFE2           | Nonce Service     | `getNonceService`, `redeemNonceService` | Nonce generation and validation           |
| RA             | VA                | `vaService`                             | Domain validation challenges              |
| RA             | SA                | `saService`                             | Database read-write operations            |
| RA             | CA                | `caService`                             | Certificate signing requests              |
| RA             | Publisher         | `publisherService`                      | Certificate Transparency submission       |
| CA             | SA                | `saService`                             | Certificate storage                       |
| CA             | RA (SCT Provider) | `sctService`                            | Signed Certificate Timestamps             |
| VA             | SA                | `saService`                             | Authorization storage                     |

## 9. Database Schema Management

Boulder uses the `sql-migrate` tool for database schema migrations. Migrations must be applied separately using dedicated migration commands before starting the `boulder-sa` service.

```bash
boulder boulder-sa --config /etc/boulder/sa.json migrate
```

The migration scripts are located in the [`sa/db`](boulder/sa/db/) directory.

## 10. Boulder-Specific Production Considerations

### Hardware Security Modules (HSMs) for Certificate Authority Operations

Boulder's CA services are designed to integrate with Hardware Security Modules (HSMs) for secure private key storage and cryptographic operations:

- **PKCS#11 Integration**: Production CA services require PKCS#11-compatible HSMs for secure private key storage
- **Key Ceremony**: The `ceremony` tool manages secure key generation and certificate signing operations with HSM integration
- **Multi-HSM Support**: Boulder supports multiple HSM configurations for different intermediate CA certificates
- **Session Management**: CA configuration specifies the number of HSM sessions per issuer for concurrent signing operations

### High Availability and Multi-Instance Architecture

Boulder's microservice architecture is designed for horizontal scaling and high availability:

- **Service Redundancy**: Core services run multiple numbered instances (e.g., `boulder-sa-1`, `boulder-sa-2`, `boulder-ca-1`, `boulder-ca-2`) for load distribution and failover
- **Geographic Distribution**: Nonce services run across multiple datacenters (`taro`, `zinc`) for geographic redundancy
- **Load Balancing**: Consul service discovery provides automatic load balancing across service instances
- **Dependency Management**: Services use health checks and circuit breakers to handle dependency failures gracefully

### Rate Limiting Implementation for ACME Compliance

Boulder implements sophisticated rate limiting to prevent abuse while maintaining ACME protocol compliance:

- **TAT-based Rate Limiting**: Uses Time After Time (TAT) values stored in Redis for distributed rate limiting
- **Sharded Redis Architecture**: Multiple Redis instances in a ring topology distribute rate limiting data
- **Account-based Limits**: Rate limits are applied per ACME account with configurable thresholds
- **Domain-based Limits**: Additional rate limiting based on domain names and certificate issuance patterns
- **Override Mechanisms**: Support for rate limit overrides for specific accounts or domains

### Certificate Transparency (CT) Integration

Boulder maintains comprehensive CT log integration for certificate transparency compliance:

- **Multi-Log Submission**: Certificates are submitted to multiple CT logs for redundancy
- **SCT Collection**: Signed Certificate Timestamps (SCTs) are collected and embedded in issued certificates
- **Log Monitoring**: The log-validator service continuously monitors CT log health and consistency
- **Precertificate Workflow**: Boulder uses precertificate submission to CT logs before final certificate issuance

## 11. Running in a Containerized Environment (Kubernetes)

To deploy Boulder in Kubernetes, you would typically:

1. **Containerize the Boulder binary:** Create a Docker image that contains the `boulder` binary. Start with the provided Boulder [`Containerfile`](boulder/Containerfile).
2. **Deploy Supporting Infrastructure:** Deploy MariaDB, Redis, and Consul to your Kubernetes cluster.
3. **Create Kubernetes Services:** For each core Boulder service, create a Kubernetes Deployment and Service.
4. **Configure Service Discovery:** Configure the Boulder services to use Kubernetes DNS for service discovery. This will involve modifying the `dnsAuthority` and `srvLookup` sections of the configuration files to match your Kubernetes service names and DNS setup.
5. **Manage PKI Secrets:** Store the IPKI and WebPKI certificates and keys in Kubernetes Secrets and mount them into the appropriate pods. For the IPKI, `cert-manager` can be used.
6. **Configure Ingress:** Create an Ingress resource to expose the WFE2 service to the public internet.

## 12. Local Integration Testing

The primary workflow for local development and testing is the [`./t.sh`](boulder/t.sh) script, which uses Docker Compose to run a full integration test suite. This is an excellent resource for understanding how the services interact and for validating changes.

The integration tests verify:

- Complete certificate issuance workflows
- Challenge validation for all supported types (HTTP-01, DNS-01, TLS-ALPN-01)
- Multi-perspective validation (MPIC)
- Certificate transparency integration
- Rate limiting functionality
- Service health and dependency management

Refer to the [`docker-compose.yml`](boulder/docker-compose.yml) file to see how the services and their dependencies are orchestrated in the test environment.
