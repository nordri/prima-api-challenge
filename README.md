# Prima Domain SRE Tech Challenge

Implementation of the **Prima Domain SRE Tech Challenge**, providing a containerized Python application together with the infrastructure, Kubernetes deployment and CI/CD required to run it.

The solution is designed to be fully testable locally using **LocalStack**, Docker and Kubernetes, while also providing the AWS/EKS-specific configuration required for a production deployment.

## Architecture

```text
                         GitHub
                            |
                      GitHub Actions
                            |
                            v
                           GHCR
                            |
                            v
                    Kubernetes / EKS
                            |
                     +------+------+
                     |             |
                  API Pod        API Pod
                     |
              ServiceAccount
                     |
                  IRSA / IAM
                  /       \
                 v         v
             DynamoDB      S3
```

For local development, AWS services are provided by LocalStack:

```text
                     Prima API
                         |
                  +------+------+
                  |             |
                  v             v
              DynamoDB          S3
                  \             /
                   \           /
                    LocalStack
```

A more detailed description is available in [Architecture](docs/ARCHITECTURE.md).

## Repository Structure

```text
.
├── app/                    # Flask application and Docker image
├── docker-compose/         # LocalStack development environment
├── terraform/              # AWS infrastructure and IAM/IRSA
├── helm/                   # Kubernetes Helm chart
├── docs/                   # Architecture and technical decisions
├── .github/workflows/      # CI/CD pipelines
└── Makefile                # Common local and CI validation interface
```

Each component contains its own documentation:

- [Application](app/README.md)
- [Terraform](terraform/README.md)
- [Helm](helm/README.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Technical Decisions](docs/technical-decisions.md)

## Components

### Application

The provided Flask application has been containerized and runs using Gunicorn as an unprivileged user.

It exposes:

```text
GET  /users
POST /user
GET  /health
GET  /swagger
```

DynamoDB is used to store users and S3 to store their avatars.

The application includes a small pytest suite covering its core behavior.

### Infrastructure

Terraform provisions:

- DynamoDB
- S3
- S3 encryption and access configuration
- IAM application policy
- EKS IRSA role and trust policy when enabled

IRSA is optional so that the same Terraform configuration can be used with LocalStack without requiring an EKS cluster.

### Kubernetes

The Helm chart provides:

- Deployment
- Service
- ServiceAccount
- Liveness and readiness probes
- Resource requests and limits
- HorizontalPodAutoscaler

The ServiceAccount supports arbitrary annotations, allowing the IAM role created by Terraform to be associated with it when deployed to EKS.

### CI/CD

GitHub Actions validates:

- Python formatting and style
- Python unit tests
- Terraform formatting and validation
- Helm linting and rendering
- Docker image build

The application image is also built and published to GitHub Container Registry using the version defined in:

```text
app/version.txt
```

The same Makefile targets used by CI can be executed locally.

## Quick Start

### Requirements

The local environment requires:

- Docker with Docker Compose
- Terraform
- Helm
- Poetry
- AWS CLI

### 1. Start LocalStack

From the repository root:

```bash
docker compose -f docker-compose/compose.yaml up -d
```

Check that LocalStack is ready:

```bash
curl http://localhost:4566/_localstack/health
```

### 2. Provision the AWS resources

```bash
cd terraform

make apply

cd ..
```

This creates the S3 bucket and DynamoDB table in LocalStack.

### 3. Run the application

The application can then be built and started using the Makefile under `app/`.

See [Application documentation](app/README.md) for the required runtime configuration and Docker commands.

### 4. Verify the application

```bash
curl http://localhost:5000/health
curl http://localhost:5000/users
```

Expected health response:

```json
{"status":"ok"}
```

Swagger UI is available at:

```text
http://localhost:5000/swagger
```

## Validate the Complete Repository

All project checks can be executed from the repository root:

```bash
make check
```

This runs the same validation used by CI:

```text
Python
  ├── Black
  ├── Flake8
  └── pytest

Terraform
  ├── format
  └── validate

Helm
  ├── lint
  └── template

Docker
  └── build
```

This command has been validated from a fresh clone of the repository to ensure that the development workflow is reproducible.

## Kubernetes Validation

The complete containerized application has also been deployed to Kubernetes using the included Helm chart.

The validation environment used:

```text
Kubernetes
    |
    +-- Helm deployment
    |     |
    |     +-- Prima API replicas
    |
    +-- LocalStack
          |
          +-- DynamoDB
          +-- S3
```

The application image published to GHCR was used by the Kubernetes deployment and successfully communicated with the Terraform-provisioned LocalStack resources.

## AWS / EKS

For an AWS deployment, LocalStack is disabled and Terraform targets the real AWS APIs.

When running on EKS, IRSA can be enabled to create a least-privilege IAM role for the application.

The resulting role is associated with the Kubernetes ServiceAccount:

```text
Pod
 |
 v
ServiceAccount
 |
 v
EKS OIDC
 |
 v
IAM Role
 |
 +----> DynamoDB
 |
 +----> S3
```

This avoids injecting static AWS credentials into the application pods.

An actual EKS cluster is intentionally not provisioned as part of this challenge.

See [Terraform documentation](terraform/README.md) for the IRSA configuration.

## Design Principles

The implementation favors:

- reproducible local development;
- least-privilege AWS permissions;
- no static AWS credentials in Kubernetes;
- runtime configuration rather than environment-specific images;
- clear separation between application, AWS infrastructure and Kubernetes concerns;
- identical validation commands locally and in CI;
- simple components justified by actual requirements rather than speculative infrastructure.

The rationale and trade-offs behind these choices are documented in [Technical Decisions](docs/technical-decisions.md).

## Version

Current application version:

```text
1.0.0
```