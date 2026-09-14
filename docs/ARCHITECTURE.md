# Architecture

## Overview

The solution provides a containerized Python API backed by AWS S3 and DynamoDB.

The repository contains all the components required to build, validate and deploy the application:

- A Flask API served by Gunicorn.
- A Docker image published to GitHub Container Registry.
- Terraform infrastructure for S3, DynamoDB and optional EKS IRSA resources.
- A Helm chart for Kubernetes deployments.
- LocalStack support for local development and integration testing.
- GitHub Actions pipelines for continuous integration and container publishing.

The solution was designed to support two main execution environments:

1. **Local / development**, using LocalStack.
2. **AWS / EKS**, using native AWS services and IRSA for authentication.

The same application image, Terraform configuration and Helm chart are used across environments. Environment-specific behavior is provided through configuration rather than separate implementations.

---

## High-Level Architecture

```text
                         GitHub
                            |
                            | push / pull request
                            v
                    +------------------+
                    |  GitHub Actions  |
                    +------------------+
                      |              |
                validation        image build
                      |              |
                      |              v
                      |             GHCR
                      |              |
                      +--------------+
                                     |
                                     v
                         +-----------------------+
                         |   Kubernetes / EKS    |
                         |                       |
                         |  +-----------------+  |
                         |  |   Prima API     |  |
                         |  |    Pod #1       |  |
                         |  +-----------------+  |
                         |                       |
                         |  +-----------------+  |
                         |  |   Prima API     |  |
                         |  |    Pod #2       |  |
                         |  +-----------------+  |
                         |           |           |
                         |     ServiceAccount    |
                         +-----------|-----------+
                                     |
                                    IRSA
                                     |
                                     v
                              +-------------+
                              |  IAM Role   |
                              +-------------+
                                /         \
                               /           \
                              v             v
                       +----------+     +--------+
                       | DynamoDB |     |   S3   |
                       +----------+     +--------+
```

Terraform provisions the AWS resources consumed by the application, while Helm is responsible for deploying and configuring the application inside Kubernetes.

This separation deliberately keeps AWS infrastructure concerns outside the Kubernetes chart.

---

## Application Architecture

The application is a small Flask API exposing the following main endpoints:

```text
GET  /users
POST /user
GET  /health
GET  /swagger
```

The application uses:

- **DynamoDB** to persist user information.
- **S3** to store uploaded avatars.
- **Gunicorn** as the application server.
- **boto3** to communicate with AWS services.

The basic request flow is:

```text
                    HTTP Request
                         |
                         v
                 +---------------+
                 |   Gunicorn    |
                 +-------+-------+
                         |
                         v
                 +---------------+
                 |     Flask     |
                 +-------+-------+
                         |
               +---------+---------+
               |                   |
               v                   v
          +----------+          +------+
          | DynamoDB |          |  S3  |
          +----------+          +------+
```

Application configuration is provided at runtime through environment variables. AWS infrastructure identifiers are therefore not embedded in the container image.

---

## Container Architecture

The application is packaged as a Docker image.

The container:

- installs dependencies using Poetry;
- runs the application with Gunicorn;
- listens on port `5000`;
- runs as an unprivileged user;
- receives environment-specific configuration at runtime.

The application version is stored in:

```text
app/version.txt
```

The same version is used when publishing the image to GitHub Container Registry.

Example:

```text
ghcr.io/nordri/prima-sre-tech-challenge:0.1.0
```

The container does not contain AWS credentials.

---

## AWS Infrastructure

Terraform manages the AWS resources required by the application.

### DynamoDB

A DynamoDB table stores user records.

The user's email address is used as the table partition key.

The application currently requires:

```text
dynamodb:Scan
dynamodb:PutItem
```

### S3

An S3 bucket stores user avatars.

The bucket configuration includes:

- server-side encryption;
- public ACL blocking;
- public-read access through bucket policy.

Using a bucket policy rather than object ACLs keeps object ownership and access management centralized at bucket level.

The application currently requires:

```text
s3:PutObject
```

### IAM

For EKS deployments, Terraform can optionally create:

```text
IAM Policy
    |
    v
IAM Role
    |
    v
EKS OIDC trust
```

The policy follows a least-privilege approach and grants access only to the S3 bucket and DynamoDB table required by the application.

IRSA creation is disabled by default because an EKS OIDC provider does not exist in LocalStack or generic local Kubernetes environments.

---

## EKS Authentication

Static AWS credentials are not intended to be injected into application pods in EKS.

Instead, the application uses IAM Roles for Service Accounts (IRSA).

```text
Application Pod
      |
      v
Kubernetes ServiceAccount
      |
      | ServiceAccount annotation
      v
EKS OIDC Provider
      |
      | sts:AssumeRoleWithWebIdentity
      v
IAM Role
      |
      v
IAM Policy
      |
      +------> DynamoDB
      |
      +------> S3
```

The IAM trust policy restricts role assumption to the configured Kubernetes identity:

```text
system:serviceaccount:<namespace>:<service-account>
```

and requires:

```text
aud = sts.amazonaws.com
```

Terraform exposes the resulting role ARN as an output.

The Helm chart accepts arbitrary ServiceAccount annotations, allowing the role to be associated with the application without introducing AWS-specific IAM logic into the chart:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <irsa-role-arn>
```

The AWS SDK running inside the application then obtains temporary credentials automatically.

---

## Kubernetes Architecture

The Helm chart deploys:

```text
ServiceAccount
      |
      v
Deployment
      |
      +---- Pod
      |
      +---- Pod
      |
      v
ClusterIP Service

Deployment
      ^
      |
HorizontalPodAutoscaler
```

The Deployment defines CPU and memory requests and limits.

Two replicas are used by default to avoid relying on a single application instance.

### Health Checks

The application exposes:

```text
GET /health
```

which is used by both:

- liveness probes;
- readiness probes.

The health endpoint verifies that the application process can serve requests.

It deliberately does not query DynamoDB or S3. A temporary downstream AWS failure should make requests depending on that service fail, but should not cause Kubernetes to continuously restart otherwise healthy application processes.

### Autoscaling

The HorizontalPodAutoscaler uses CPU utilization as its scaling signal.

The default configuration is:

```text
minimum replicas: 2
maximum replicas: 5
target CPU:      70%
```

This provides a simple baseline that can later be replaced or complemented with application-specific metrics if production traffic characteristics justify it.

---

## Local Development Architecture

Local development uses LocalStack to emulate the AWS services required by the application.

```text
                   Developer Machine
                          |
          +---------------+---------------+
          |                               |
          v                               v
   +-------------+                 +-------------+
   |  Prima API  |                 |  Terraform  |
   |  Container  |                 +------+------+
   +------+------+                        |
          |                               |
          +---------------+---------------+
                          |
                          v
                   +-------------+
                   | LocalStack  |
                   |             |
                   | S3          |
                   | DynamoDB    |
                   +-------------+
```

LocalStack is started using the Docker Compose configuration included in the repository.

Terraform uses the same S3 and DynamoDB resource definitions used for AWS, but directs the AWS provider to LocalStack.

IAM/IRSA resources are omitted in this environment.

This provides a lightweight way to validate infrastructure and application integration without requiring access to a real AWS account.

---

## Kubernetes Validation Environment

The complete deployment has also been validated in a Kubernetes environment using KillerCoda.

The validation architecture was:

```text
                KillerCoda
                    |
          +---------+---------+
          |                   |
          v                   v
     Kubernetes           LocalStack
          |                :4566
          |
     Helm release
          |
       Service
          |
     +----+----+
     |         |
    Pod       Pod
     |         |
     +----+----+
          |
          v
     LocalStack
      /      \
     v        v
 DynamoDB     S3
```

Terraform provisioned the S3 and DynamoDB resources in LocalStack before the Helm deployment.

The application image used by Kubernetes was the image built by GitHub Actions and published to GHCR.

The validation confirmed:

- successful Helm installation;
- two Ready application pods;
- working liveness and readiness probes;
- working Kubernetes Service;
- successful `/health` requests;
- successful `/users` requests against DynamoDB.

The HPA resource was also successfully deployed. KillerCoda did not provide a Metrics API in the validation environment, so CPU utilization remained unavailable to the HPA.

A real EKS deployment was intentionally not required for the challenge.

---

## CI/CD Architecture

The repository uses GitHub Actions for CI and container publication.

```text
                   Developer
                       |
                       v
                  git push / PR
                       |
                       v
               +----------------+
               | GitHub Actions |
               +----------------+
                 /    |    |    \
                /     |    |     \
               v      v    v      v
           Python Terraform Helm Docker
            checks  checks checks build
                \     |     |     /
                 \    |     |    /
                  +---+-----+---+
                          |
                     successful
                          |
                          v
                         GHCR
```

The validation workflow checks:

- Python formatting with Black;
- Python style with Flake8;
- Python unit tests with pytest;
- Terraform formatting and validation;
- Helm linting and template rendering;
- Docker image build.

The actual validation commands live in the repository Makefile rather than being duplicated inside GitHub Actions.

This allows the same checks to be executed locally:

```bash
make check
```

and by CI.

This design reduces differences between developer and CI environments and makes the validation process easier to reproduce and debug.

---

## Design Decisions

### Terraform instead of Pulumi

The challenge allows either Terraform or Pulumi.

Terraform was selected because it provides a concise and well-understood way to express the required AWS infrastructure and allowed the implementation to focus on infrastructure design, IAM and application deployment rather than introducing an additional abstraction.

### LocalStack for local validation

The infrastructure can be exercised without depending on access to a real AWS account.

LocalStack also allows the application, Terraform and Kubernetes layers to be tested together.

### Optional IRSA

IRSA depends on an existing EKS OIDC provider.

Rather than attempting to emulate this locally, IRSA resources are created only when explicitly enabled for an AWS/EKS environment.

This keeps local deployments simple while preserving the intended production authentication model.

### Least-privilege IAM

The application IAM policy contains only the operations currently performed by the application and restricts them to its S3 bucket and DynamoDB table.

Broad permissions such as:

```text
s3:*
dynamodb:*
```

are intentionally avoided.

### No static AWS credentials in Kubernetes

Production EKS workloads are expected to obtain temporary credentials through IRSA.

Long-lived AWS credentials therefore do not need to be stored in Helm values, Kubernetes Secrets or container images.

### Generic Helm ServiceAccount annotations

The Helm chart does not implement IRSA directly.

Instead, it exposes generic ServiceAccount annotations. Terraform manages the AWS identity and Helm consumes its ARN.

This keeps the Kubernetes chart reusable and separates infrastructure responsibilities.

### Reproducible validation

The Makefile acts as the common interface for project validation.

Both developers and GitHub Actions execute the same targets, reducing duplicated CI logic and configuration drift.

### Simple health endpoint

The health endpoint intentionally checks application availability rather than the complete dependency graph.

This prevents failures in external services from triggering unnecessary pod restart loops.

---

## Production Considerations

The challenge implementation provides the core infrastructure and deployment model, but a production system would require additional decisions based on expected traffic, availability requirements and operational constraints.

Areas to consider include:

- structured application logging;
- application and business metrics;
- SLI/SLO definitions and alerting;
- distributed tracing where useful;
- more extensive unit and integration testing;
- DynamoDB pagination for large datasets;
- stronger avatar content validation beyond filename extensions;
- S3 lifecycle and retention requirements;
- Terraform remote state and locking;
- container vulnerability scanning;
- PodDisruptionBudgets where availability requirements justify them;
- topology spread or pod anti-affinity for multi-node clusters;
- NetworkPolicies where supported by the chosen CNI;
- an ingress/load-balancing strategy;
- TLS and DNS management;
- deployment strategies such as rolling, canary or blue/green;
- GitOps or another controlled production deployment mechanism.

These have deliberately not been added simply to increase the number of components in the solution. Their implementation should follow actual production requirements and operational constraints rather than being assumed by default.
