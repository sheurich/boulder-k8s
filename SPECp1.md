# Phase 1 Spec: Kubernetes-Based Boulder Integration Environment

## Objective

Containerize and deploy Let's Encrypt's Boulder services into a Kubernetes cluster to run its integration test suite in a pod-based microservice architecture.

## Requirements

### Microservices as Pods

- Each Boulder mode (e.g., `sa`, `ra`, `va`, etc.) must be deployed as an independent Kubernetes pod.
- Use a single container image with different command-line arguments for each role.

### Service Discovery

- Replace Consul DNS with Kubernetes services for service-to-service communication.

### Configuration Management

- Use Kubernetes ConfigMaps and Secrets to manage:
  - Database credentials
  - Redis connection strings
  - TLS certificates and keys
  - Boulder configuration files

### Supporting Services

- Include Redis and PostgreSQL as Kubernetes services.
- Deploy a software-based HSM simulator (e.g., SoftHSM or fakeHSM) in-cluster. Use a PKCS#11 proxy to connect boulder-ca with an HSM container over the network.

### Integration Testing

- Replicate Boulder’s Python-based integration test scripts to run against the Kubernetes cluster.
- Ensure all inter-service dependencies (e.g., VA requires SA) are met at startup.

## Deliverables

- Kubernetes manifests (YAMLs) for all services and configurations.
- A bash script or Makefile to deploy the stack on `kind` (Kubernetes in Docker).
- README with deployment and test instructions.
