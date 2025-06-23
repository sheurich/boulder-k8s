
# Docker Compose Inventory

This document provides an inventory of the services defined in the Docker Compose setup for the Boulder project.

## Data Gathering Process

The data was gathered by programmatically parsing the `docker-compose.yml` and `docker-compose.next.yml` files using a Python script with the PyYAML library. The script merges the configurations, with the `next` file overriding the base file.

Environment variables from `.env` files were not explicitly found or parsed, as the provided docker-compose files did not reference any.

## Ambiguities and Resolutions

- **Service Type:** The `service_type` was inferred based on the service name. This is a best-effort guess and should be reviewed.
- **Secrets:** Values for environment variables that look like secrets (containing keywords like `password`, `secret`, `key`, `token`) or are short have been redacted to `<redacted>`.
- **`needs_init`:** This flag was set to `true` for services that call scripts like `start-servers.py` or `generate.sh`, or are explicitly for setup purposes (like `bsetup`). This is an inference based on the provided instructions.
- **Duplicate Services:** The `boulder` service is defined in both `docker-compose.yml` and `docker-compose.next.yml`. The definitions were merged, with the `environment` from `docker-compose.next.yml` overriding the one in the base file. This is flagged as per instructions.

## Open Questions for the Migration Team

1.  Are the inferred `service_type` tags accurate for all services?
2.  Are there any other services or configurations that are generated dynamically in a CI/CD pipeline that were not captured?
3.  The `FAKE_DNS` environment variable is hardcoded in the compose files. How should this be handled in Kubernetes?
4.  Are there any other implicit dependencies between services that are not captured in the `depends_on` field?
