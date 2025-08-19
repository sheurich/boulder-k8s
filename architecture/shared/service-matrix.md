# Boulder Services Matrix

This document provides detailed specifications for each Boulder service, including configuration requirements, network ports, health checks, and resource requirements for Kubernetes deployment.

## ⚠️ OCSP Services Exclusion Notice

**IMPORTANT**: This Kubernetes deployment **excludes all OCSP-related services** as they are deprecated in Boulder and slated for removal. The following OCSP services are **NOT** implemented:

- **OCSP Responder** - ❌ **EXCLUDED** (deprecated)
- **OCSP Generator** - ❌ **EXCLUDED** (deprecated)
- **OCSP Updater** - ❌ **EXCLUDED** (deprecated)
- **Akamai Purger** - ❌ **EXCLUDED** (deprecated)

This exclusion simplifies the deployment without affecting core ACME certificate issuance functionality.

## Core ACME Services

### Web Front End (WFE2)

| Property | Value |
|----------|-------|
| **Service Name** | boulder-wfe2 |
| **Purpose** | Public-facing ACME API endpoint that receives and validates client requests |
| **Command** | `boulder boulder-wfe2 --config /etc/boulder/wfe2.json` |
| **Ports** | - 4001 (HTTP API)<br>- 4431 (HTTPS API)<br>- 8013 (Debug/Metrics) |
| **Dependencies** | boulder-ra, boulder-sa, nonce-service, email-exporter |
| **Replicas** | 1 (can scale horizontally) |

#### Configuration Requirements
```json
{
  "wfe": {
    "listenAddress": "0.0.0.0:4001",
    "tlsListenAddress": "0.0.0.0:4431",
    "raService": {
      "serverAddress": "boulder-ra:9394",
      "hostOverride": "ra.boulder"
    },
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "getNonceService": {
      "serverAddress": "nonce-service:9501",
      "hostOverride": "nonce.boulder"
    },
    "redeemNonceService": {
      "serverAddresses": [
        "nonce-service:9501",
        "nonce-service:9502"
      ]
    }
  }
}
```

#### Environment Variables
- `BOULDER_CONFIG_DIR`: `/etc/boulder`
- `GRPC_GO_LOG_VERBOSITY_LEVEL`: `2`
- `GRPC_GO_LOG_SEVERITY_LEVEL`: `info`

#### Health Check
- **Endpoint**: `http://localhost:8013/debug/health`
- **Initial Delay**: 30s
- **Period**: 10s
- **Timeout**: 5s

#### Resource Requirements
- **CPU Request**: 500m
- **CPU Limit**: 2000m
- **Memory Request**: 512Mi
- **Memory Limit**: 2Gi

---

### Registration Authority (RA)

| Property | Value |
|----------|-------|
| **Service Name** | boulder-ra |
| **Purpose** | Orchestrates certificate issuance workflow and manages account operations |
| **Command** | `boulder boulder-ra --config /etc/boulder/ra.json` |
| **Ports** | - 9394/9494 (gRPC)<br>- 8002/8102 (Debug/Metrics) |
| **Dependencies** | boulder-sa, boulder-ca, boulder-va, boulder-publisher |
| **Replicas** | 2 (boulder-ra-1, boulder-ra-2) |

#### Configuration Requirements
```json
{
  "ra": {
    "grpcAddress": ":9394",
    "debugAddr": ":8002",
    "vaService": {
      "serverAddress": "boulder-va:9392",
      "hostOverride": "va.boulder"
    },
    "caService": {
      "serverAddress": "boulder-ca:9393",
      "hostOverride": "ca.boulder"
    },
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "publisherService": {
      "serverAddress": "boulder-publisher:9391",
      "hostOverride": "publisher.boulder"
    },
    "limiter": {
      "redis": {
        "server": "redis:6379",
        "password": "${REDIS_PASSWORD}"
      }
    }
  }
}
```

#### Environment Variables
- `BOULDER_CONFIG_DIR`: `/etc/boulder`
- `REDIS_PASSWORD`: (from Secret)

#### Health Check
- **Endpoint**: `http://localhost:8002/debug/health`
- **Initial Delay**: 45s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 1000m
- **CPU Limit**: 4000m
- **Memory Request**: 1Gi
- **Memory Limit**: 4Gi

---

### Certificate Authority (CA)

| Property | Value |
|----------|-------|
| **Service Name** | boulder-ca |
| **Purpose** | Signs certificates, generates CRLs, manages private keys |
| **Command** | `boulder boulder-ca --config /etc/boulder/ca.json` |
| **Ports** | - 9393/9493 (gRPC)<br>- 8001/8101 (Debug/Metrics) |
| **Dependencies** | boulder-sa, boulder-ra-sct-provider |
| **Replicas** | 2 (boulder-ca-1, boulder-ca-2) |
| **Note** | ❌ **OCSP generation excluded** (deprecated functionality) |

#### Configuration Requirements
```json
{
  "ca": {
    "grpcAddress": ":9393",
    "debugAddr": ":8001",
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "sctService": {
      "serverAddress": "boulder-ra-sct-provider:9594",
      "hostOverride": "ra.boulder"
    },
    "issuance": {
      "certProfiles": {
        "legacy": {
          "maxValidityPeriod": "7776000s",
          "maxValidityBackdate": "1h5m"
        }
      },
      "issuers": [
        {
          "location": {
            "configFile": "/etc/boulder/pkcs11/int-ecdsa-a.json",
            "certFile": "/etc/boulder/certs/int-ecdsa-a.cert.pem",
            "numSessions": 2
          }
        }
      ]
    }
  }
}
```

#### Secrets Required
- WebPKI certificates and keys
- PKCS#11 configuration files

#### Health Check
- **Endpoint**: `http://localhost:8001/debug/health`
- **Initial Delay**: 30s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 1000m
- **CPU Limit**: 4000m
- **Memory Request**: 1Gi
- **Memory Limit**: 4Gi

---

### Storage Authority (SA)

| Property | Value |
|----------|-------|
| **Service Name** | boulder-sa |
| **Purpose** | Database abstraction layer for all Boulder data operations |
| **Command** | `boulder boulder-sa --config /etc/boulder/sa.json` |
| **Ports** | - 9395/9495 (gRPC)<br>- 8003/8103 (Debug/Metrics) |
| **Dependencies** | ProxySQL, MariaDB |
| **Replicas** | 2 (boulder-sa-1, boulder-sa-2) |

#### Configuration Requirements
```json
{
  "sa": {
    "grpcAddress": ":9395",
    "debugAddr": ":8003",
    "db": {
      "dbConnectFile": "/etc/boulder/secrets/sa_dburl",
      "maxOpenConns": 100,
      "maxIdleConns": 50,
      "connMaxLifetime": "5m",
      "connMaxIdleTime": "1m"
    },
    "readOnlyDB": {
      "dbConnectFile": "/etc/boulder/secrets/sa_ro_dburl",
      "maxOpenConns": 100
    },
    "incidentsDB": {
      "dbConnectFile": "/etc/boulder/secrets/incidents_dburl",
      "maxOpenConns": 10
    }
  }
}
```

#### Secrets Required
- `sa_dburl`: Primary database connection string
- `sa_ro_dburl`: Read-only database connection string
- `incidents_dburl`: Incidents database connection string

#### Health Check
- **Endpoint**: `http://localhost:8003/debug/health`
- **Initial Delay**: 20s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 500m
- **CPU Limit**: 2000m
- **Memory Request**: 512Mi
- **Memory Limit**: 2Gi

---

### Validation Authority (VA)

| Property | Value |
|----------|-------|
| **Service Name** | boulder-va |
| **Purpose** | Performs domain validation challenges (HTTP-01, DNS-01, TLS-ALPN-01) |
| **Command** | `boulder boulder-va --config /etc/boulder/va.json` |
| **Ports** | - 9392/9492 (gRPC)<br>- 8004/8104 (Debug/Metrics) |
| **Dependencies** | remoteva services, boulder-sa |
| **Replicas** | 2 (boulder-va-1, boulder-va-2) |

#### Configuration Requirements
```json
{
  "va": {
    "grpcAddress": ":9392",
    "debugAddr": ":8004",
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "remoteVAs": [
      {
        "serverAddress": "remoteva-a:9397",
        "timeout": "15s",
        "hostOverride": "rva1.boulder"
      },
      {
        "serverAddress": "remoteva-b:9498",
        "timeout": "15s",
        "hostOverride": "rva2.boulder"
      }
    ],
    "dnsProvider": {
      "server": "unbound:53"
    }
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8004/debug/health`
- **Initial Delay**: 30s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 500m
- **CPU Limit**: 2000m
- **Memory Request**: 512Mi
- **Memory Limit**: 2Gi

---

## Supporting Services

### Publisher

| Property | Value |
|----------|-------|
| **Service Name** | boulder-publisher |
| **Purpose** | Submits certificates to CT logs and retrieves SCTs |
| **Command** | `boulder boulder-publisher --config /etc/boulder/publisher.json` |
| **Ports** | - 9391/9491 (gRPC)<br>- 8009/8109 (Debug/Metrics) |
| **Dependencies** | None (connects to external CT logs) |
| **Replicas** | 2 (boulder-publisher-1, boulder-publisher-2) |

#### Configuration Requirements
```json
{
  "publisher": {
    "grpcAddress": ":9391",
    "debugAddr": ":8009",
    "ctLogs": [
      {
        "uri": "http://ct-test-srv:4600",
        "key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEYggOxPnPkzKBIhTacSYoIfnSL2jPugcbUKx83vFMvk5gKAz/AGe87w20riuPwEGn229hKVbEKHFB61NIqNHC3Q=="
      }
    ]
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8009/debug/health`
- **Initial Delay**: 20s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 200m
- **CPU Limit**: 1000m
- **Memory Request**: 256Mi
- **Memory Limit**: 1Gi

---

### Nonce Service

| Property | Value |
|----------|-------|
| **Service Name** | nonce-service |
| **Purpose** | Generates and validates single-use nonces for replay protection |
| **Command** | `boulder nonce-service --config /etc/boulder/nonce-service.json` |
| **Ports** | - 9501/9502 (gRPC)<br>- 8021/8022 (Debug/Metrics) |
| **Dependencies** | Redis |
| **Replicas** | 2-4 (geographic distribution) |

#### Configuration Requirements
```json
{
  "nonceService": {
    "grpcAddress": ":9501",
    "debugAddr": ":8021",
    "redis": {
      "server": "redis:6379",
      "password": "${REDIS_PASSWORD}",
      "maxRetries": 3,
      "timeout": "5s"
    },
    "prefix": "taro"
  }
}
```

#### Environment Variables
- `REDIS_PASSWORD`: (from Secret)

#### Health Check
- **Endpoint**: `http://localhost:8021/debug/health`
- **Initial Delay**: 15s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Memory Request**: 128Mi
- **Memory Limit**: 512Mi

---

### Remote VA Services

| Property | Value |
|----------|-------|
| **Service Name** | remoteva-a/b/c |
| **Purpose** | Performs validation from different network perspectives (MPIC) |
| **Command** | `boulder remoteva --config /etc/boulder/remoteva-{a,b,c}.json` |
| **Ports** | - 9397/9498/9499 (gRPC)<br>- 8011/8012/8023 (Debug/Metrics) |
| **Dependencies** | None |
| **Replicas** | 1 per perspective (3 total) |

#### Configuration Requirements
```json
{
  "va": {
    "grpcAddress": ":9397",
    "debugAddr": ":8011",
    "perspective": "dadaist",
    "rir": "ARIN",
    "dnsProvider": {
      "server": "unbound:53"
    }
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8011/debug/health`
- **Initial Delay**: 20s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 200m
- **CPU Limit**: 1000m
- **Memory Request**: 256Mi
- **Memory Limit**: 1Gi

---

### SCT Provider (RA variant)

| Property | Value |
|----------|-------|
| **Service Name** | boulder-ra-sct-provider |
| **Purpose** | Specialized RA for SCT operations in development |
| **Command** | `boulder boulder-ra --config /etc/boulder/ra-sct-provider.json` |
| **Ports** | - 9594/9694 (gRPC)<br>- 8118/8119 (Debug/Metrics) |
| **Dependencies** | boulder-publisher |
| **Replicas** | 2 |

#### Configuration Requirements
```json
{
  "ra": {
    "grpcAddress": ":9594",
    "debugAddr": ":8118",
    "publisherService": {
      "serverAddress": "boulder-publisher:9391",
      "hostOverride": "publisher.boulder"
    }
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8118/debug/health`
- **Initial Delay**: 25s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 200m
- **CPU Limit**: 1000m
- **Memory Request**: 256Mi
- **Memory Limit**: 1Gi

---

## Administrative Services

### Self-service Front End (SFE)

| Property | Value |
|----------|-------|
| **Service Name** | sfe |
| **Purpose** | Web portal for self-service account management |
| **Command** | `boulder sfe --config /etc/boulder/sfe.json` |
| **Ports** | - 4003 (HTTP)<br>- 8015 (Debug/Metrics) |
| **Dependencies** | boulder-ra, boulder-sa |
| **Replicas** | 1 |

#### Configuration Requirements
```json
{
  "sfe": {
    "listenAddress": ":4003",
    "debugAddr": ":8015",
    "raService": {
      "serverAddress": "boulder-ra:9394",
      "hostOverride": "ra.boulder"
    },
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    }
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8015/debug/health`
- **Initial Delay**: 30s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Memory Request**: 128Mi
- **Memory Limit**: 512Mi

---

### CRL Storer

| Property | Value |
|----------|-------|
| **Service Name** | crl-storer |
| **Purpose** | Manages CRL storage and distribution |
| **Command** | `boulder crl-storer --config /etc/boulder/crl-storer.json` |
| **Ports** | - 9503/9603 (gRPC)<br>- 8024/8124 (Debug/Metrics) |
| **Dependencies** | boulder-sa |
| **Replicas** | 2 |

#### Configuration Requirements
```json
{
  "crlStorer": {
    "grpcAddress": ":9503",
    "debugAddr": ":8024",
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "s3": {
      "endpoint": "s3-test-srv:4501",
      "bucket": "crl-bucket",
      "region": "us-east-1"
    }
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8024/debug/health`
- **Initial Delay**: 20s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Memory Request**: 128Mi
- **Memory Limit**: 512Mi

---

### Bad Key Revoker

| Property | Value |
|----------|-------|
| **Service Name** | bad-key-revoker |
| **Purpose** | Monitors and revokes certificates with compromised keys |
| **Command** | `boulder bad-key-revoker --config /etc/boulder/bad-key-revoker.json` |
| **Ports** | - 9504 (gRPC)<br>- 8025 (Debug/Metrics) |
| **Dependencies** | boulder-sa |
| **Replicas** | 1 |

#### Configuration Requirements
```json
{
  "badKeyRevoker": {
    "grpcAddress": ":9504",
    "debugAddr": ":8025",
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "checkInterval": "1h",
    "batchSize": 1000
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8025/debug/health`
- **Initial Delay**: 20s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Memory Request**: 128Mi
- **Memory Limit**: 512Mi

---

### Log Validator

| Property | Value |
|----------|-------|
| **Service Name** | log-validator |
| **Purpose** | Validates CT log submissions and monitors log health |
| **Command** | `boulder log-validator --config /etc/boulder/log-validator.json` |
| **Ports** | - 9505 (gRPC)<br>- 8026 (Debug/Metrics) |
| **Dependencies** | boulder-sa |
| **Replicas** | 1 |

#### Configuration Requirements
```json
{
  "logValidator": {
    "grpcAddress": ":9505",
    "debugAddr": ":8026",
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "ctLogs": [
      {
        "uri": "http://ct-test-srv:4600",
        "key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEYggOxPnPkzKBIhTacSYoIfnSL2jPugcbUKx83vFMvk5gKAz/AGe87w20riuPwEGn229hKVbEKHFB61NIqNHC3Q=="
      }
    ]
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8026/debug/health`
- **Initial Delay**: 20s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Memory Request**: 128Mi
- **Memory Limit**: 512Mi

---

### Email Exporter

| Property | Value |
|----------|-------|
| **Service Name** | email-exporter |
| **Purpose** | Exports email metrics and handles notifications |
| **Command** | `boulder email-exporter --config /etc/boulder/email-exporter.json` |
| **Ports** | - 9506 (gRPC)<br>- 8027 (Debug/Metrics) |
| **Dependencies** | boulder-sa |
| **Replicas** | 1 |

#### Configuration Requirements
```json
{
  "emailExporter": {
    "grpcAddress": ":9506",
    "debugAddr": ":8027",
    "saService": {
      "serverAddress": "boulder-sa:9395",
      "hostOverride": "sa.boulder"
    },
    "smtp": {
      "server": "localhost:25",
      "from": "noreply@example.com"
    }
  }
}
```

#### Health Check
- **Endpoint**: `http://localhost:8027/debug/health`
- **Initial Delay**: 20s
- **Period**: 10s

#### Resource Requirements
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Memory Request**: 128Mi
- **Memory Limit**: 512Mi

---

## Infrastructure Services

### MariaDB

| Property | Value |
|----------|-------|
| **Service Type** | StatefulSet |
| **Purpose** | Primary relational database for all Boulder data |
| **Image** | mariadb:10.5 |
| **Port** | 3306 |
| **Storage** | 10Gi PersistentVolume |

#### Environment Variables
- `MYSQL_ROOT_PASSWORD`: (from Secret)
- `MYSQL_DATABASE`: boulder
- `MYSQL_USER`: boulder
- `MYSQL_PASSWORD`: (from Secret)

#### Resource Requirements
- **CPU Request**: 1000m
- **CPU Limit**: 4000m
- **Memory Request**: 2Gi
- **Memory Limit**: 8Gi

---

### ProxySQL

| Property | Value |
|----------|-------|
| **Service Type** | Deployment |
| **Purpose** | Database proxy for connection pooling and load balancing |
| **Image** | proxysql/proxysql:2.5 |
| **Ports** | - 6033 (MySQL interface)<br>- 6032 (Admin interface) |
| **Dependencies** | MariaDB |

#### Configuration
```ini
mysql_servers =
(
    {
        address="mariadb",
        port=3306,
        hostgroup=0,
        max_connections=1000
    }
)

mysql_users =
(
    {
        username="boulder",
        password="${MYSQL_PASSWORD}",
        default_hostgroup=0,
        max_connections=200
    }
)
```

#### Resource Requirements
- **CPU Request**: 500m
- **CPU Limit**: 2000m
- **Memory Request**: 512Mi
- **Memory Limit**: 2Gi

---

### Redis

| Property | Value |
|----------|-------|
| **Service Type** | StatefulSet |
| **Purpose** | Rate limiting and nonce storage |
| **Image** | redis:7-alpine |
| **Port** | 6379 |
| **Instances** | 2 (sharded) |
| **Storage** | 1Gi PersistentVolume per instance |

#### Configuration
```conf
requirepass ${REDIS_PASSWORD}
maxmemory 256mb
maxmemory-policy allkeys-lru
save ""
appendonly no
```

#### Resource Requirements
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Memory Request**: 256Mi
- **Memory Limit**: 512Mi

---

## Common Configuration Elements

### mTLS Certificates (Internal PKI)

All Boulder services require the following certificates for inter-service communication:

| File | Purpose | Mount Path |
|------|---------|------------|
| `minica.pem` | Internal CA certificate | `/etc/boulder/certs/minica.pem` |
| `{service}.boulder/cert.pem` | Service certificate | `/etc/boulder/certs/{service}.boulder/cert.pem` |
| `{service}.boulder/key.pem` | Service private key | `/etc/boulder/certs/{service}.boulder/key.pem` |

### WebPKI Certificates (CA Operations)

The CA service requires additional certificates for signing operations:

| File | Purpose | Mount Path |
|------|---------|------------|
| `root-rsa.cert.pem` | RSA root certificate | `/etc/boulder/webpki/root-rsa.cert.pem` |
| `root-ecdsa.cert.pem` | ECDSA root certificate | `/etc/boulder/webpki/root-ecdsa.cert.pem` |
| `int-{type}-{id}.cert.pem` | Intermediate certificates | `/etc/boulder/webpki/int-{type}-{id}.cert.pem` |
| `int-{type}-{id}.pkcs11.json` | PKCS#11 configs | `/etc/boulder/pkcs11/int-{type}-{id}.json` |

### Logging Configuration

All services use structured JSON logging with the following configuration:

```json
{
  "syslog": {
    "stdoutLevel": 6,
    "syslogLevel": 6
  }
}
```

Log levels:
- 0: Emergency
- 1: Alert
- 2: Critical
- 3: Error
- 4: Warning
- 5: Notice
- 6: Info
- 7: Debug

### Network Policies

Services should only communicate with their declared dependencies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: boulder-ra-network-policy
spec:
  podSelector:
    matchLabels:
      app: boulder-ra
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: boulder-wfe2
    ports:
    - protocol: TCP
      port: 9394
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: boulder-sa
    - podSelector:
        matchLabels:
          app: boulder-ca
    - podSelector:
        matchLabels:
          app: boulder-va
    - podSelector:
        matchLabels:
          app: boulder-publisher
```

### Service Account RBAC

Each service should run with minimal permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: boulder-service
  namespace: boulder
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: boulder-service
  namespace: boulder
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: boulder-service
  namespace: boulder
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: boulder-service
subjects:
- kind: ServiceAccount
  name: boulder-service
  namespace: boulder
```

## Deployment Considerations

### Service Startup Order

Services must start in the following order to satisfy dependencies:

1. **Infrastructure** (Parallel)
   - MariaDB
   - Redis
   - ProxySQL (after MariaDB)

2. **Foundation** (Parallel)
   - remoteva-a/b/c
   - boulder-sa-1/2 (after ProxySQL)
   - boulder-publisher-1/2

3. **Validation** (After remoteva)
   - boulder-va-1/2

4. **Certificate** (After publisher)
   - boulder-ra-sct-provider-1/2
   - boulder-ca-1/2 (after SA + SCT)

5. **Registration** (After CA, VA, SA)
   - boulder-ra-1/2

6. **Web** (After RA, SA)
   - nonce-service-1/2 (after Redis)
   - boulder-wfe2
   - sfe

7. **Support** (After SA)
   - crl-storer
   - bad-key-revoker
   - log-validator
   - email-exporter

### Init Container Pattern

Use init containers to verify dependencies are ready:

```yaml
initContainers:
- name: wait-for-sa
  image: busybox:1.35
  command: ['sh', '-c', 'until nslookup boulder-sa; do sleep 2; done']
- name: wait-for-ca
  image: busybox:1.35
  command: ['sh', '-c', 'until nslookup boulder-ca; do sleep 2; done']
```

### Graceful Shutdown

Configure proper termination grace periods:

```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
  - name: boulder-service
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 15"]
```

### Monitoring and Alerting

Key metrics to monitor:

- **Service Health**: All `/debug/health` endpoints returning 200
- **Certificate Issuance Rate**: Certificates issued per minute
- **Validation Success Rate**: Successful vs failed validations
- **Database Connections**: Active connections and pool usage
- **Redis Memory**: Memory usage and eviction rate
- **Request Latency**: P50, P95, P99 latencies per service
- **Error Rates**: 4xx and 5xx responses from WFE2

### Security Hardening

**Note**: Advanced security hardening features are planned for Phase 2. Phase 1 focuses on basic security practices:

1. **Resource limits**: Always set CPU and memory limits
2. **Basic security contexts**: Non-root execution where possible
3. **Secret management**: Sensitive data in Kubernetes Secrets

Advanced security features (Phase 2):
- Pod Security Standards enforcement
- Network policies for traffic restriction  
- Read-only root filesystems
- Capability dropping
- Runtime security scanning
