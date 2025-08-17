# Boulder ACME API Usage Guide

This document provides comprehensive guidance on using the ACME protocol with Boulder CA deployed on Kubernetes, including practical examples and common workflows.

## Table of Contents

- [ACME Protocol Overview](#acme-protocol-overview)
- [Boulder API Endpoints](#boulder-api-endpoints)
- [Getting Started](#getting-started)
- [ACME Client Examples](#acme-client-examples)
- [Certificate Issuance Workflow](#certificate-issuance-workflow)
- [Challenge Types](#challenge-types)
- [Rate Limiting](#rate-limiting)
- [Error Handling](#error-handling)
- [Advanced Usage](#advanced-usage)
- [API Reference](#api-reference)

## ACME Protocol Overview

The Automatic Certificate Management Environment (ACME) protocol automates the process of certificate issuance, renewal, and revocation. Boulder implements ACME v2 (RFC 8555) with full compliance.

### Key ACME Concepts

- **Account**: Represents a client identity with the CA
- **Order**: A request for one or more certificates
- **Authorization**: Proves control over a domain
- **Challenge**: Method to validate domain control
- **Certificate**: The issued X.509 certificate

### ACME Workflow

```
Client                    Boulder CA
  |                          |
  | 1. Create Account        |
  |------------------------->|
  |                          |
  | 2. Submit Order          |
  |------------------------->|
  |                          |
  | 3. Fetch Challenges      |
  |------------------------->|
  |                          |
  | 4. Complete Challenge    |
  |------------------------->|
  |                          |
  | 5. Poll for Completion   |
  |------------------------->|
  |                          |
  | 6. Download Certificate  |
  |------------------------->|
```

### Important: OCSP Exclusion

**⚠️ Note**: This Boulder deployment excludes OCSP functionality (deprecated). Certificate revocation status is provided through Certificate Transparency logs and CRL distribution points.

## Boulder API Endpoints

### Base URL

```
http://localhost:4001  # Development (kind cluster)
https://localhost:4431 # Development (HTTPS)
```

For external access, use appropriate LoadBalancer IP or Ingress configuration.

### Directory Endpoint

The ACME directory provides URLs for all protocol operations:

```bash
curl -s http://localhost:4001/directory | jq .
```

**Response:**
```json
{
  "newAccount": "http://localhost:4001/acme/new-account",
  "newNonce": "http://localhost:4001/acme/new-nonce", 
  "newOrder": "http://localhost:4001/acme/new-order",
  "revokeCert": "http://localhost:4001/acme/revoke-cert",
  "keyChange": "http://localhost:4001/acme/key-change",
  "meta": {
    "termsOfService": "http://localhost:4001/terms",
    "website": "https://github.com/letsencrypt/boulder",
    "caaIdentities": ["boulder.service.consul"]
  }
}
```

### Core Endpoints

| Endpoint | Purpose | Method |
|----------|---------|--------|
| `/directory` | Get directory URLs | GET |
| `/acme/new-nonce` | Get fresh nonce | HEAD/GET |
| `/acme/new-account` | Create ACME account | POST |
| `/acme/new-order` | Submit certificate order | POST |
| `/acme/authz/{id}` | Get authorization details | GET |
| `/acme/chall/{id}` | Respond to challenge | POST |
| `/acme/order/{id}` | Get order status | GET |
| `/acme/cert/{id}` | Download certificate | GET |
| `/acme/revoke-cert` | Revoke certificate | POST |

## Getting Started

### Prerequisites

Ensure Boulder is deployed and accessible:

```bash
# Check Boulder deployment
./k8s/scripts/health-check.sh

# Test ACME directory
curl -s http://localhost:4001/directory
```

### Access Configuration

#### Local Development (kind)
```bash
# Port forward for local access
kubectl port-forward service/boulder-wfe2 4001:4001 -n boulder

# Test connectivity
curl -s http://localhost:4001/directory
```

#### External Access
```bash
# Get LoadBalancer IP (if configured)
kubectl get service boulder-wfe2 -n boulder

# Or use Ingress
kubectl get ingress -n boulder
```

## ACME Client Examples

### Using Certbot

Certbot is the official ACME client from the Electronic Frontier Foundation.

#### Installation

```bash
# Ubuntu/Debian
sudo apt-get install certbot

# macOS
brew install certbot

# Other platforms: https://certbot.eff.org/instructions
```

#### Account Registration

```bash
# Register new account
certbot register \
  --server http://localhost:4001/acme/directory \
  --email admin@example.com \
  --agree-tos \
  --no-eff-email
```

#### Certificate Issuance

**HTTP-01 Challenge (Standalone):**
```bash
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --standalone \
  --domains example.com
```

**HTTP-01 Challenge (Webroot):**
```bash
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --webroot \
  --webroot-path /var/www/html \
  --domains example.com
```

**DNS-01 Challenge (Manual):**
```bash
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --manual \
  --preferred-challenges dns \
  --domains example.com
```

**Multiple Domains:**
```bash
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --standalone \
  --domains example.com,www.example.com,api.example.com
```

#### Certificate Renewal

```bash
# Renew all certificates
certbot renew --server http://localhost:4001/acme/directory

# Renew specific certificate
certbot renew \
  --server http://localhost:4001/acme/directory \
  --cert-name example.com
```

### Using acme.sh

acme.sh is a lightweight, pure shell implementation of the ACME protocol.

#### Installation

```bash
curl https://get.acme.sh | sh -s email=admin@example.com
source ~/.bashrc
```

#### Certificate Issuance

**HTTP-01 Challenge (Standalone):**
```bash
acme.sh --issue \
  --server http://localhost:4001/acme/directory \
  --domain example.com \
  --standalone
```

**HTTP-01 Challenge (Webroot):**
```bash
acme.sh --issue \
  --server http://localhost:4001/acme/directory \
  --domain example.com \
  --webroot /var/www/html
```

**DNS-01 Challenge (Manual):**
```bash
acme.sh --issue \
  --server http://localhost:4001/acme/directory \
  --domain example.com \
  --dns dns_manual
```

**Wildcard Certificate:**
```bash
acme.sh --issue \
  --server http://localhost:4001/acme/directory \
  --domain "*.example.com" \
  --dns dns_manual
```

#### Certificate Installation

```bash
# Install to nginx
acme.sh --install-cert \
  --domain example.com \
  --key-file /etc/nginx/ssl/example.com.key \
  --fullchain-file /etc/nginx/ssl/example.com.pem \
  --reloadcmd "systemctl reload nginx"

# Install to apache
acme.sh --install-cert \
  --domain example.com \
  --key-file /etc/httpd/ssl/example.com.key \
  --fullchain-file /etc/httpd/ssl/example.com.pem \
  --reloadcmd "systemctl reload httpd"
```

### Using curl (Manual ACME)

For educational purposes or custom implementations:

#### 1. Get Directory

```bash
curl -s http://localhost:4001/directory | jq .
```

#### 2. Get Fresh Nonce

```bash
NONCE=$(curl -I -s http://localhost:4001/acme/new-nonce | \
  grep -i replay-nonce | cut -d' ' -f2 | tr -d '\r\n')
echo "Nonce: $NONCE"
```

#### 3. Create Account

```bash
# Generate account key
openssl genrsa -out account.key 2048

# Create account (requires proper JWS signing)
# This is complex - use existing ACME clients for production
```

## Certificate Issuance Workflow

### Step-by-Step Process

#### 1. Account Creation

Every ACME client must first create an account:

```bash
certbot register \
  --server http://localhost:4001/acme/directory \
  --email admin@example.com \
  --agree-tos
```

#### 2. Order Submission

Submit an order for certificate issuance:

```bash
# This is handled automatically by ACME clients
# Manual example would require JWS signing
```

#### 3. Authorization and Challenges

Boulder will respond with challenges to prove domain control:

- **HTTP-01**: Place a file at `http://{domain}/.well-known/acme-challenge/{token}`
- **DNS-01**: Create DNS TXT record at `_acme-challenge.{domain}`
- **TLS-ALPN-01**: Present special certificate on port 443

#### 4. Challenge Completion

Complete the challenge and notify Boulder:

```bash
# For HTTP-01 with standalone server
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --standalone \
  --domains example.com

# Certbot automatically:
# 1. Starts HTTP server on port 80
# 2. Places challenge response
# 3. Notifies Boulder
# 4. Polls for completion
# 5. Downloads certificate
```

#### 5. Certificate Download

Once validated, download the certificate:

```bash
# Certificates stored in /etc/letsencrypt/live/{domain}/
ls -la /etc/letsencrypt/live/example.com/

# Files:
# cert.pem       - Domain certificate only
# chain.pem      - Intermediate certificate(s)
# fullchain.pem  - Domain + intermediate certificates
# privkey.pem    - Private key
```

## Challenge Types

Boulder supports three ACME challenge types for domain validation:

### HTTP-01 Challenge

Proves control by placing a file on the web server.

**Requirements:**
- Port 80 accessible from internet
- Ability to serve files from `/.well-known/acme-challenge/`

**Example with nginx:**
```bash
# Allow certbot to use webroot
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --webroot \
  --webroot-path /var/www/html \
  --domains example.com

# nginx configuration needed:
# location /.well-known/acme-challenge/ {
#     root /var/www/html;
# }
```

**Advantages:**
- Simple to set up
- No DNS configuration required
- Works with shared hosting

**Limitations:**
- Cannot issue wildcard certificates
- Requires port 80 access
- Domain must be publicly accessible

### DNS-01 Challenge

Proves control by creating a DNS TXT record.

**Requirements:**
- Ability to create DNS TXT records
- DNS propagation time (usually minutes)

**Manual Example:**
```bash
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --manual \
  --preferred-challenges dns \
  --domains example.com

# Certbot will display:
# Create TXT record: _acme-challenge.example.com
# Value: random-token-string
```

**Automated with DNS Provider:**
```bash
# Example with Cloudflare
export CLOUDFLARE_EMAIL="admin@example.com"
export CLOUDFLARE_API_KEY="your-api-key"

certbot certonly \
  --server http://localhost:4001/acme/directory \
  --dns-cloudflare \
  --dns-cloudflare-credentials ~/.secrets/cloudflare.ini \
  --domains example.com,*.example.com
```

**Advantages:**
- Can issue wildcard certificates
- Works with private/internal servers
- No port 80 requirement

**Limitations:**
- Requires DNS API access
- DNS propagation delays
- More complex setup

### TLS-ALPN-01 Challenge

Proves control via TLS certificate on port 443.

**Requirements:**
- Port 443 accessible from internet
- TLS server supporting ALPN extension

**Example:**
```bash
# Limited client support
# Mainly used by specialized servers
```

**Advantages:**
- Uses port 443 (commonly open)
- No webroot requirement
- Fast validation

**Limitations:**
- Cannot issue wildcard certificates
- Requires TLS-ALPN support
- Limited client support

## Rate Limiting

Boulder implements rate limiting to prevent abuse:

### Default Limits

| Limit Type | Default Value | Window |
|------------|---------------|--------|
| **New Registrations** | 10 per IP | 3 hours |
| **New Orders** | 300 per account | 3 hours |
| **Failed Validations** | 5 per hostname | 1 hour |
| **Certificates per Domain** | 50 per week | 7 days |
| **Duplicate Certificates** | 5 per week | 7 days |

### Rate Limit Headers

Boulder returns rate limit information in headers:

```bash
curl -I http://localhost:4001/acme/new-order

# Response headers:
# X-RateLimit-Limit: 300
# X-RateLimit-Remaining: 299
# X-RateLimit-Reset: 1609459200
```

### Handling Rate Limits

**Check Current Usage:**
```bash
# Use certbot dry-run to check limits
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --standalone \
  --domains example.com \
  --dry-run
```

**Strategies:**
- Use staging environment for testing
- Implement exponential backoff
- Monitor rate limit headers
- Batch certificate requests efficiently

## Error Handling

### Common ACME Errors

#### Account Errors

**Account Not Found (404):**
```json
{
  "type": "urn:ietf:params:acme:error:accountDoesNotExist",
  "detail": "Account not found"
}
```
*Solution: Register new account*

#### Authorization Errors

**DNS Resolution Failed:**
```json
{
  "type": "urn:ietf:params:acme:error:dns",
  "detail": "DNS problem: NXDOMAIN looking up A for example.com"
}
```
*Solution: Verify DNS configuration*

**Connection Failed:**
```json
{
  "type": "urn:ietf:params:acme:error:connection",
  "detail": "Connection refused"
}
```
*Solution: Check firewall and server configuration*

#### Challenge Errors

**Incorrect Response:**
```json
{
  "type": "urn:ietf:params:acme:error:incorrectResponse",
  "detail": "Invalid response from challenge"
}
```
*Solution: Verify challenge response content*

**Unauthorized:**
```json
{
  "type": "urn:ietf:params:acme:error:unauthorized",
  "detail": "Account not authorized"
}
```
*Solution: Complete domain validation*

#### Rate Limit Errors

**Too Many Requests:**
```json
{
  "type": "urn:ietf:params:acme:error:rateLimited",
  "detail": "Too many requests for this registration"
}
```
*Solution: Wait for rate limit reset*

### Error Troubleshooting

#### Check Boulder Logs

```bash
# Check WFE2 logs for API errors
kubectl logs deployment/boulder-wfe2 -n boulder | grep ERROR

# Check RA logs for processing errors
kubectl logs deployment/boulder-ra -n boulder | grep ERROR

# Check VA logs for validation errors
kubectl logs deployment/boulder-va -n boulder | grep ERROR
```

#### Debug with Verbose Output

```bash
# Certbot verbose mode
certbot certonly \
  --server http://localhost:4001/acme/directory \
  --standalone \
  --domains example.com \
  --verbose

# acme.sh debug mode
acme.sh --issue \
  --server http://localhost:4001/acme/directory \
  --domain example.com \
  --standalone \
  --debug
```

## Advanced Usage

### Custom ACME Clients

Building custom ACME clients requires:

1. **JWS Signing**: All requests must be signed with account key
2. **Nonce Management**: Include fresh nonce in each request
3. **Base64URL Encoding**: Proper encoding of all JSON payloads
4. **Error Handling**: Robust error parsing and retry logic

#### Example Libraries

**Python:**
```python
from acme import client, messages
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa

# Generate account key
private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
)

# Create ACME client
directory_url = "http://localhost:4001/acme/directory"
net = client.ClientNetwork(private_key)
directory = messages.Directory.from_json(net.get(directory_url).json())
acme_client = client.ClientV2(directory, net=net)
```

**Go:**
```go
import (
    "crypto/rsa"
    "golang.org/x/crypto/acme"
)

client := &acme.Client{
    DirectoryURL: "http://localhost:4001/acme/directory",
}

// Generate account key
key, _ := rsa.GenerateKey(rand.Reader, 2048)

// Create account
account := &acme.Account{
    Contact: []string{"mailto:admin@example.com"},
}
```

### Certificate Automation

#### Automated Renewal

**Systemd Timer (Linux):**
```bash
# /etc/systemd/system/certbot-renew.service
[Unit]
Description=Certbot Renewal

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --server http://localhost:4001/acme/directory

# /etc/systemd/system/certbot-renew.timer
[Unit]
Description=Run certbot twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
```

**Cron Job:**
```bash
# Renew certificates twice daily
0 0,12 * * * /usr/bin/certbot renew --server http://localhost:4001/acme/directory --quiet
```

**Kubernetes CronJob:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cert-renewal
spec:
  schedule: "0 */12 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: certbot
            image: certbot/certbot
            command:
            - /bin/sh
            - -c
            - certbot renew --server http://boulder-wfe2.boulder:4001/acme/directory
          restartPolicy: OnFailure
```

### Multi-Perspective Validation

Boulder performs multi-perspective issuance corroboration (MPIC) to enhance security:

```bash
# Check validation from multiple perspectives
kubectl logs deployment/boulder-va -n boulder | grep "perspective"

# Remote VA validation
kubectl logs deployment/remote-va1 -n boulder
kubectl logs deployment/remote-va2 -n boulder
```

This ensures domain validation succeeds from multiple network vantage points.

## API Reference

### Authentication

All ACME requests (except directory and nonce) require:
- **JWS Signature**: Request signed with account private key
- **Nonce**: Fresh nonce from `/acme/new-nonce`
- **URL**: Target URL in JWS protected header

### Request Format

```http
POST /acme/new-account HTTP/1.1
Host: localhost:4001
Content-Type: application/jose+json

{
  "protected": "base64url-encoded-header",
  "payload": "base64url-encoded-payload", 
  "signature": "base64url-encoded-signature"
}
```

### Response Format

**Success Response:**
```http
HTTP/1.1 201 Created
Content-Type: application/json
Location: https://localhost:4001/acme/acct/123

{
  "status": "valid",
  "contact": ["mailto:admin@example.com"],
  "termsOfServiceAgreed": true
}
```

**Error Response:**
```http
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json

{
  "type": "urn:ietf:params:acme:error:malformed",
  "detail": "Invalid signature",
  "status": 400
}
```

### Status Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 200 | OK | Request successful |
| 201 | Created | Resource created |
| 202 | Accepted | Request accepted, processing |
| 400 | Bad Request | Invalid request format |
| 401 | Unauthorized | Authentication failed |
| 403 | Forbidden | Account not authorized |
| 404 | Not Found | Resource not found |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |

---

This API usage guide provides comprehensive examples for using Boulder's ACME implementation. For troubleshooting specific issues, refer to [TROUBLESHOOTING.md](TROUBLESHOOTING.md).