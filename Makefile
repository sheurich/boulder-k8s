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

# Deploy Boulder services to Kubernetes cluster
deploy: lint
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

.PHONY: all lint setup deploy health-check test-integration test bootstrap clean status
