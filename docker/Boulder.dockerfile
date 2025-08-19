# syntax=docker/dockerfile:1

# Boulder version configuration -
# override with a specific commit or tag for reproducibility
ARG BOULDER_TAG="main"
ARG BOULDER_REPO="https://github.com/letsencrypt/boulder.git"

# Go version - override with a specific version for reproducibility
ARG GOLANG_VER="1"

# Image metadata build arguments
ARG IMAGE_VENDOR="unknown"
ARG BUILD_REVISION="unknown"
ARG BUILD_DATE="unknown"

# Base images with specific tags for reproducibility
# For CGO builds (required for PKCS#11 HSM support), the builder and deployer
# images must be ABI-compatible (e.g. based on the same Debian version).
# To use a different base image, build statically with CGO_ENABLED=0,
# which will disable HSM support.
ARG BUILDER_IMAGE="golang:${GOLANG_VER}-bookworm"
ARG DEPLOYER_IMAGE="gcr.io/distroless/base-debian12:latest"

# Build configuration
ARG CGO_ENABLED=1
ARG GOARCH=${TARGETARCH}
ARG GOOS=${TARGETOS}

# Builder Stage
FROM "${BUILDER_IMAGE}" AS builder
ARG BOULDER_REPO
ARG BOULDER_TAG
ARG CGO_ENABLED
ARG GOARCH
ARG GOOS

RUN --mount=type=cache,target=/tmp/git-cache \
    git clone --depth 1 --branch "${BOULDER_TAG}" \
    "${BOULDER_REPO}" \
    /src/boulder
WORKDIR /src/boulder
RUN set -eux; \
    GIT_NAME="$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || echo detached)"; \
    GIT_SHA="$(git rev-parse --short=8 HEAD)"; \
    BUILD_ID="${GIT_NAME}@${GIT_SHA}"; \
    BUILD_TIME="$(git show -s --format=%cI HEAD)"; \
    BUILD_HOST="${GOOS}/${GOARCH}"; \
    make BUILD_ID="${BUILD_ID}" BUILD_TIME="${BUILD_TIME}" BUILD_HOST="${BUILD_HOST}"

RUN bin/boulder --version

# Runtime Stage
FROM "${DEPLOYER_IMAGE}" AS runtime
ARG BUILD_DATE
ARG BUILD_REVISION
ARG IMAGE_VENDOR

LABEL \
    org.opencontainers.image.title="Boulder" \
    org.opencontainers.image.description="Let's Encrypt ACME server implementation" \
    org.opencontainers.image.vendor="${IMAGE_VENDOR}" \
    org.opencontainers.image.licenses="MPL-2.0" \
    org.opencontainers.image.url="https://github.com/letsencrypt/boulder" \
    org.opencontainers.image.source="https://github.com/letsencrypt/boulder" \
    org.opencontainers.image.documentation="https://github.com/letsencrypt/boulder/blob/main/docs/" \
    org.opencontainers.image.revision="${BUILD_REVISION}" \
    org.opencontainers.image.created="${BUILD_DATE}"

COPY --from=builder --chmod=555 \
    /src/boulder/bin/* /opt/boulder/bin/
COPY --from=builder --chmod=755 \
    /src/boulder/data /opt/boulder/data
COPY --from=builder --chmod=755 \
    /src/boulder/sa/db /opt/boulder/sa/db
COPY --from=builder --chmod=755 \
    /src/boulder/test/config /opt/boulder/test/config

USER nonroot

ENV PATH="/opt/boulder/bin:${PATH}"

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/opt/boulder/bin/boulder", "--version"]

ENTRYPOINT ["/opt/boulder/bin/boulder"]
