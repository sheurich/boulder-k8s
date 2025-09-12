setup:
    @echo "Setting up the environment..."
    just kind_create
    just deploy_cert_manager
    just deploy_mariadb_operator
    just deploy_mariadb_instance
    just prime_db

test:
    @echo "Running tests..."
    just setup
    just test_db
    just teardown

teardown:
    @echo "Tearing down the environment..."
    just kind_delete

kind_create:
    @echo "Creating kind cluster..."
    kind create cluster --name boulder-k8s --config kind-config.yaml

kind_delete:
    @echo "Deleting kind cluster..."
    kind delete cluster --name boulder-k8s

deploy_cert_manager:
    @echo "Deploying cert-manager..."
    helm repo add jetstack https://charts.jetstack.io || true
    helm repo update
    helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true -f k8s/helm/cert-manager-values.yaml
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager --namespace cert-manager --timeout=120s

deploy_mariadb_operator:
    @echo "Deploying MariaDB operator..."
    helm repo add mariadb-operator https://mariadb-operator.github.io/mariadb-operator || true
    helm repo update
    @echo "Installing MariaDB CRDs..."
    kubectl apply -f https://github.com/mariadb-operator/mariadb-operator/releases/latest/download/crds.yaml
    helm install mariadb-operator mariadb-operator/mariadb-operator --namespace mariadb-system --create-namespace -f k8s/helm/mariadb-operator-values.yaml
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mariadb-operator --namespace mariadb-system --timeout=90s
    @echo "Waiting for MariaDB operator webhook to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mariadb-operator-webhook --namespace mariadb-system --timeout=90s

deploy_mariadb_instance:
    @echo "Deploying MariaDB instance..."
    # Deploy certificates first
    kubectl apply -f k8s/manifests/certificates.yaml
    kubectl apply -f k8s/manifests/ca-issuer.yaml
    @echo "Waiting for certificates to be ready..."
    kubectl wait --for=condition=ready certificate --all --timeout=120s
    # Deploy MariaDB instance after webhook is confirmed ready
    @echo "Verifying MariaDB operator webhook is responding..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mariadb-operator-webhook --namespace mariadb-system --timeout=30s
    # Apply MariaDB instance with retry for webhook readiness
    @echo "Applying MariaDB instance (with webhook retry)..."
    until kubectl apply -f k8s/manifests/mariadb-instance.yaml; do \
        echo "Webhook not ready, retrying in 5 seconds..."; \
        sleep 5; \
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mariadb-operator-webhook --namespace mariadb-system --timeout=30s || true; \
    done
    @echo "Fixing CA secret format for MariaDB operator..."
    kubectl apply -f k8s/jobs/fix-ca-secret-job.yaml
    kubectl wait --for=condition=complete job/fix-ca-secret-job --namespace default --timeout=60s
    kubectl wait --for=condition=ready mariadb boulder-mariadb --namespace default --timeout=180s

prime_db:
    @echo "Priming the database..."
    kubectl apply -f k8s/jobs/db-priming-job.yaml
    kubectl wait --for=condition=complete job/db-priming-job --namespace default --timeout=300s

test_db:
    @echo "Testing the database..."
    kubectl apply -f k8s/jobs/test-db-job.yaml
    kubectl wait --for=condition=complete job/test-db-job --namespace default --timeout=60s
    kubectl logs job/test-db-job
