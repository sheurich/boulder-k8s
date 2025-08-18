# syntax=docker/dockerfile:1

ARG BOULDER_TAG="main"
ARG GOLANG_VER="1"

ARG BUILDER_IMAGE="golang:${GOLANG_VER}-bookworm"
ARG DEPLOYER_IMAGE="gcr.io/distroless/base-debian12"

FROM ${BUILDER_IMAGE} AS builder
ARG BOULDER_TAG
RUN git clone --depth 1 --branch "$BOULDER_TAG" https://github.com/letsencrypt/boulder.git /go/src/github.com/letsencrypt/boulder
WORKDIR /go/src/github.com/letsencrypt/boulder
RUN set -eux; \
    GIT_NAME="$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || echo detached)"; \
    GIT_SHA="$(git rev-parse --short=8 HEAD)"; \
    BUILD_ID="${GIT_NAME}@${GIT_SHA}"; \
    BUILD_TIME="$(git show -s --format=%cI HEAD)"; \
    BUILD_HOST="$(go env GOOS)/$(go env GOARCH)"; \
    make BUILD_ID="$BUILD_ID" BUILD_TIME="$BUILD_TIME" BUILD_HOST="$BUILD_HOST"
RUN bin/boulder --version

FROM ${DEPLOYER_IMAGE}
LABEL org.opencontainers.image.title="Boulder"

COPY --from=builder --chmod=0555 \
    /go/src/github.com/letsencrypt/boulder/bin/* /opt/boulder/bin/
COPY --from=builder /go/src/github.com/letsencrypt/boulder/data /opt/boulder/data
COPY --from=builder /go/src/github.com/letsencrypt/boulder/sa/db /opt/boulder/sa/db
COPY --from=builder /go/src/github.com/letsencrypt/boulder/test/config /opt/boulder/test/config

USER nonroot

ENV PATH="/opt/boulder/bin:${PATH}"
ENTRYPOINT ["/opt/boulder/bin/boulder"]
