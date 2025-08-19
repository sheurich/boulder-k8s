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
deploy: setup docker-build setup-tls
	@echo "Deploying Boulder services..."
	./k8s/scripts/deploy.sh

# Run health checks on Boulder services
health-check: deploy
	@echo "Running Boulder health checks..."
	./k8s/scripts/health-check.sh

# Run integration tests for Boulder ACME functionality
test-integration: deploy
	@echo "Running Boulder integration tests..."
	./k8s/scripts/run-integration-tests.sh

# Run all tests (health check followed by integration tests)
test: health-check test-integration
	@echo "All Boulder tests completed successfully"

# Complete setup and deployment workflow
bootstrap: deploy health-check
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

# Show comprehensive deployment status with health verification
status:
	@echo "=== Cluster Status ===" && kubectl cluster-info || echo "No cluster available"
	@echo ""
	@echo "=== Boulder Namespace Pods ===" && kubectl get pods -n boulder -o wide || echo "Boulder namespace not found"
	@echo ""
	@echo "=== Boulder Services ===" && kubectl get services -n boulder || echo "Boulder namespace not found"
	@echo ""
	@echo "=== Certificate Status ===" && kubectl get certificates -n boulder -o custom-columns="NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,SECRET:.spec.secretName,AGE:.metadata.creationTimestamp" 2>/dev/null || echo "No certificates found"
	@echo ""
	@echo "=== cert-manager Status ===" && kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager not found"
	@echo ""
	@echo "=== Service Health Summary ==="
	@kubectl get pods -n boulder --no-headers 2>/dev/null | while read name ready status restarts age node; do \
		if [ "$$status" = "Running" ] && [ "$${ready%/*}" = "$${ready#*/}" ]; then \
			echo "✅ $$name - Ready"; \
		elif [ "$$status" = "Running" ]; then \
			echo "⚠️  $$name - Running but not ready ($${ready})"; \
		elif [ "$$status" = "Completed" ]; then \
			echo "✅ $$name - Completed"; \
		else \
			echo "❌ $$name - $$status ($${ready})"; \
		fi; \
	done || echo "Boulder namespace not found"
	@echo ""
	@echo "=== Recent Pod Events (Errors/Warnings) ==="
	@kubectl get events -n boulder --field-selector type!=Normal --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "No recent events or Boulder namespace not found"
	@echo ""
	@echo "💡 TIP: For detailed service logs, use: kubectl logs <pod-name> -n boulder"
	@echo "💡 TIP: For service-specific health, check logs for 'SERVING' status"

.PHONY: all lint setup deploy setup-tls health-check test-integration test bootstrap clean status docker-build