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

# Run project tests
test:
	@echo "Running Boulder K8s tests..."
	@echo "Not implemented yet"

.PHONY: all lint clean test
