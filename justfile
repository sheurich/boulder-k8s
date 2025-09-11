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

kind_delete:
    @echo "Deleting kind cluster..."

deploy_cert_manager:
    @echo "Deploying cert-manager..."

deploy_mariadb_operator:
    @echo "Deploying MariaDB operator..."

deploy_mariadb_instance:
    @echo "Deploying MariaDB instance..."

prime_db:
    @echo "Priming the database..."

test_db:
    @echo "Testing the database..."
