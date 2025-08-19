# Makefile for boulder-k8s project
#
# This Makefile provides targets for project maintenance, deployment, and validation

# Default target - run linting and validation
all: lint

# Run linting checks on all file types
# Uses yamllint, kubeconform, shellcheck, markdownlint, and checkmake
lint:
	./scripts/lint.sh

# Create Kind cluster for local development
setup: lint
	@echo "Creating Kind cluster for Boulder..."
	kind create cluster --name boulder-k8s --config kind-config.yaml
	@echo "Verifying cluster access..."
	kubectl cluster-info
	kubectl get nodes

# Deploy TLS infrastructure (cert-manager and certificates)
setup-tls:
	@echo "Deploying cert-manager and TLS certificates..."
	./k8s/scripts/setup-tls.sh

# Deploy Boulder services to Kubernetes cluster
deploy: lint docker-build setup-tls
	@echo "Deploying Boulder services..."
	./k8s/scripts/deploy.sh

# Run health checks on Boulder services
health-check:
	@echo "Running Boulder health checks..."
	./k8s/scripts/health-check.sh

# Run integration tests for Boulder ACME functionality
test-integration:
	@echo "Running Boulder integration tests..."
	./k8s/scripts/run-integration-tests.sh

# Run all tests (health check followed by integration tests)
test: health-check test-integration
	@echo "All Boulder tests completed successfully"

# Complete setup and deployment workflow
bootstrap: setup deploy health-check
	@echo "Boulder deployment bootstrap completed successfully"

#
## --------------------------------------
## Docker Image Management
## --------------------------------------
DOCKER_IMAGE ?= boulder-k8s
DOCKER_TAG ?= latest
# BOULDER_VERSION defaults to 'main' for development builds.
# For production, this should be overridden with a specific git tag or commit SHA.
# Example: make docker-build \
# 	BOULDER_VERSION=v0.20250812.0 GOLANG_VERSION=1.24.6 \
# 	DOCKER_TAG=${BOULDER_VERSION}-go${GOLANG_VERSION}
BOULDER_VERSION ?= main
GOLANG_VERSION ?= 1

# Build metadata for OCI labels
IMAGE_VENDOR ?= boulder-k8s
# Use the commit hash for the revision
BUILD_REVISION := $(shell git rev-parse HEAD)
# Use the commit date for a deterministic build date (ISO 8601 format)
BUILD_DATE := $(shell git show -s --format=%cI HEAD)

# Build Boulder Docker image using build arguments
docker-build:
	@echo "Building Boulder Docker image..."
	@echo "  Vendor:    $(IMAGE_VENDOR)"
	@echo "  Source:    Boulder $(BOULDER_VERSION) / Go $(GOLANG_VERSION)"
	@echo "  Revision:  $(BUILD_REVISION)"
	@echo "  Date:      $(BUILD_DATE)"
	@echo "  Output:    $(DOCKER_IMAGE):$(DOCKER_TAG)"
	DOCKER_BUILDKIT=1 docker build \
		--file docker/Boulder.dockerfile \
		--build-arg BOULDER_TAG=$(BOULDER_VERSION) \
		--build-arg GOLANG_VER=$(GOLANG_VERSION) \
		--build-arg IMAGE_VENDOR="$(IMAGE_VENDOR)" \
		--build-arg BUILD_REVISION="$(BUILD_REVISION)" \
		--build-arg BUILD_DATE="$(BUILD_DATE)" \
		--tag $(DOCKER_IMAGE):$(DOCKER_TAG) \
		docker/

# Clean up Kind cluster and temporary files
clean:
	@echo "Cleaning up Kind cluster..."
	-kind delete cluster --name boulder-k8s
	@echo "Cleanup completed"

# Show deployment status
status:
	@echo "=== Cluster Status ===" && kubectl cluster-info || echo "No cluster available"
	@echo "=== Boulder Namespace Pods ===" && kubectl get pods -n boulder -o wide || echo "Boulder namespace not found"
	@echo "=== Boulder Services ===" && kubectl get services -n boulder || echo "Boulder namespace not found"

.PHONY: all lint setup deploy setup-tls health-check test-integration test bootstrap clean status docker-build