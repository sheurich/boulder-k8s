# Architecture

This document outlines the architecture for the WebPKI Certification Authority (CA) project.

## 1. Introduction

This project aims to create a complete set of Infrastructure as Code (IaC) specifications to deploy and operate a publicly-trusted WebPKI Certification Authority. The environment will be deployable on various platforms including local development setups, cloud providers, and bare metal servers.

## 2. Goals and Principles

- **Security**: The highest priority. The system must be secure by design and default.
- **Auditability**: All actions must be logged and auditable to comply with public trust requirements.
- **Automation**: The entire lifecycle of the CA should be automated.
- **Portability**: The IaC should be adaptable to different environments (local, cloud, bare metal).
- **Modularity**: Components should be loosely coupled and independently deployable/testable.

## 3. High-Level Architecture

The system is designed to run on Kubernetes. It consists of several key components that interact to provide the CA functionality.

![High-Level Architecture Diagram](placeholder.png) <!-- Placeholder for a diagram -->

### Components

- **CA Core Services**: The core of the CA will be an instance of Let's Encrypt's Boulder software. Boulder provides the ACME-based services for certificate issuance, revocation, and management.
- **HSM Integration**: A layer for integrating with Hardware Security Modules (HSMs) for key management. This will have mock and real implementations.
- **Public-Facing Services**: ACME servers, OCSP responders, CRL distribution points.
- **Internal Services**: Database, logging, monitoring, and alerting systems.
- **IaC Tooling**: Terraform, Helm charts, and custom scripts for deployment and management.

### Core CA Software: Boulder

The core of this project is [Let's Encrypt's Boulder](https://github.com/letsencrypt/boulder), an ACME-based Certificate Authority written in Go. It is the same software that runs the Let's Encrypt service.

Boulder has a component-based architecture that separates concerns by security context:
- Web Front End (WFE)
- Registration Authority (RA)
- Validation Authority (VA)
- Certificate Authority (CA)
- Storage Authority (SA)
- Publisher
- OCSP Responder
- CRL Updater

This project will treat Boulder as a critical component, likely managed as a git submodule to track a specific version. The IaC specifications will be responsible for configuring and deploying these Boulder components into a Kubernetes cluster.

## 4. Deployment Environments

- **Local**: Docker Desktop with Kubernetes for development and testing.
- **Cloud**: Target major cloud providers (AWS, GCP, Azure) using their managed Kubernetes services (EKS, GKE, AKS).
- **Bare Metal**: Using a Kubernetes distribution suitable for on-premises deployment (e.g., Kubeadm, k3s).
