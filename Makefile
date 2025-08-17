# Makefile for boulder-k8s project
#
# This Makefile provides targets for project maintenance and validation

# Default target - run linting and validation
all: lint

# Run linting checks on all file types
# Uses yamllint, kubeconform, shellcheck, markdownlint, and checkmake
lint:
	./scripts/lint.sh

# Clean up temporary files and build artifacts
clean:
	@echo "Cleaning up temporary files..."
	@echo "Not implemented yet"

# Run health checks on Boulder services
test-health:
	@echo "Running Boulder health checks..."
	./k8s/scripts/health-check.sh

# Run integration tests for Boulder ACME functionality
test-integration:
	@echo "Running Boulder integration tests..."
	./k8s/scripts/run-integration-tests.sh

# Run all tests (health check followed by integration tests)
test: test-health test-integration
	@echo "All Boulder tests completed successfully"

.PHONY: all lint clean test test-health test-integration
