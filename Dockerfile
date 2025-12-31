# syntax=docker/dockerfile:1
#
# Boulder ACME CA - Multi-architecture Docker build
#
# Build: docker build -t boulder:latest .
# Build with args: docker build --build-arg VERSION=1.0.0 -t boulder:1.0.0 .
#
# This Dockerfile uses the official Go image which properly handles
# multi-architecture builds (amd64, arm64) without cross-compilation issues.

# =============================================================================
# Build stage
# =============================================================================
FROM golang:1.25-bookworm AS builder

# Build arguments
ARG COMMIT_ID=unknown
ARG VERSION=dev
ARG TARGETOS
ARG TARGETARCH

WORKDIR /src/boulder

# Copy dependency files first for better layer caching
COPY boulder/go.mod boulder/go.sum ./
COPY boulder/vendor/ ./vendor/

# Copy source code
COPY boulder/ .

# Build all Boulder binaries
# CGO_ENABLED=1 required for certain Boulder functionality
# -s -w strips debug info for smaller binaries
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=1 \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go install \
        -buildvcs=false \
        -ldflags="-s -w \
            -X 'github.com/letsencrypt/boulder/core.BuildID=${COMMIT_ID}' \
            -X 'github.com/letsencrypt/boulder/core.BuildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)'" \
        -mod=vendor \
        ./cmd/...

# Build test servers (for dev/test environments)
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=1 \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    go build \
        -buildvcs=false \
        -ldflags="-s -w" \
        -mod=vendor \
        -o /go/bin/ \
        ./test/aia-test-srv \
        ./test/chall-test-srv \
        ./test/ct-test-srv \
        ./test/pardot-test-srv \
        ./test/zendesk-test-srv \
        ./test/s3-test-srv

# =============================================================================
# Runtime stage - Debian slim
# =============================================================================
FROM debian:bookworm-slim AS runtime

ARG VERSION=dev

LABEL org.opencontainers.image.title="Boulder"
LABEL org.opencontainers.image.description="Boulder is an ACME-compatible X.509 Certificate Authority"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.source="https://github.com/letsencrypt/boulder"
LABEL org.opencontainers.image.licenses="MPL-2.0"
LABEL org.opencontainers.image.vendor="Internet Security Research Group"

# Install runtime dependencies:
# - ca-certificates: TLS verification
# - libc6: required for cgo binaries
# - softhsm2: Software HSM for dev/CI PKI ceremony
# - openssl: For internal PKI certificate generation
# - curl: For downloading kubectl
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        softhsm2 \
        openssl \
        curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -u 1000 -s /usr/sbin/nologin boulder \
    && mkdir -p /var/lib/softhsm/tokens \
    && chown -R boulder:boulder /var/lib/softhsm

# Install kubectl for PKI ceremony secret creation
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Copy binaries from builder
COPY --from=builder /go/bin/ /usr/local/bin/

# Copy data files needed at runtime
COPY --from=builder /src/boulder/data /opt/boulder/data
COPY --from=builder /src/boulder/sa/db /opt/boulder/sa/db

# Copy test configs (useful for dev, small footprint)
COPY --from=builder /src/boulder/test/config /opt/boulder/test/config

WORKDIR /opt/boulder

# Run as non-root user
USER boulder

ENV PATH="/usr/local/bin:${PATH}"

# No default entrypoint - K8s deployments specify the command via args

# =============================================================================
# Distroless variant - more secure, smaller attack surface
# =============================================================================
FROM gcr.io/distroless/cc-debian12:nonroot AS distroless

ARG VERSION=dev

LABEL org.opencontainers.image.title="Boulder"
LABEL org.opencontainers.image.description="Boulder is an ACME-compatible X.509 Certificate Authority"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.source="https://github.com/letsencrypt/boulder"
LABEL org.opencontainers.image.licenses="MPL-2.0"
LABEL org.opencontainers.image.vendor="Internet Security Research Group"

# Copy binaries from builder
COPY --from=builder /go/bin/ /usr/local/bin/

# Copy data files needed at runtime
COPY --from=builder /src/boulder/data /opt/boulder/data
COPY --from=builder /src/boulder/sa/db /opt/boulder/sa/db

WORKDIR /opt/boulder

ENV PATH="/usr/local/bin:${PATH}"

# No default entrypoint - K8s deployments specify the command via args
