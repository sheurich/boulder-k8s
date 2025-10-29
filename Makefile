.PHONY: lint test deploy deps

YAML_FILES := $(shell find k8s -type f -name '*.yaml' -o -name '*.yml')

deps:
	@echo "Setting up virtual environment..."
	@python3 -m venv .venv
	@. .venv/bin/activate && pip install pre-commit && pre-commit install
	@mkdir -p $${HOME}/.local/bin
	@if ! command -v kubeconform &> /dev/null; then \
	  echo "Installing kubeconform..."; \
	  curl -sSL https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-darwin-arm64.tar.gz | tar xz -C $${HOME}/.local/bin; \
	fi
	@echo "export PATH=\"$${HOME}/.local/bin:$${PATH}\" >> $${HOME}/.zshrc"
	@export PATH="$${HOME}/.local/bin:$${PATH}"

lint: deps
	@echo "Linting Kubernetes manifests..."
	@. .venv/bin/activate && pre-commit run --all-files

test:
	@echo "Running smoke tests..."
	@./test.sh

deploy:
	@echo "Applying Kubernetes manifests..."
	@kubectl apply -f k8s/
