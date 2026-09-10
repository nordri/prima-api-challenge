# Infrastructure

This directory contains the Terraform configuration required by the Prima Senior SRE Technical Challenge.

The infrastructure provisions the AWS resources required by the application:

- An S3 bucket for storing user avatars.
- A DynamoDB table for storing user information.

The configuration supports both **LocalStack** for local development and **AWS**.

LocalStack is the default target to prevent accidental deployment to an AWS account.

## Prerequisites

The following tools are required:

- Terraform >= 1.15
- Docker and Docker Compose
- AWS CLI
- GNU Make

For local development, LocalStack must be running and accessible at:

```text
http://localhost:4566
```

## Terraform resources

The current configuration creates:

- S3 bucket for user avatars.
- S3 public access block.
- S3 server-side encryption configuration.
- DynamoDB users table using `email` as the partition key.

The DynamoDB table uses the `PAY_PER_REQUEST` billing mode.

## Directory structure

```text
terraform/
├── backend.tf
├── providers.tf
├── variables.tf
├── locals.tf
├── s3.tf
├── dynamodb.tf
├── Makefile
└── README.md
```

Terraform automatically loads all `.tf` files in the directory as part of the same root module.

## LocalStack

LocalStack is the default deployment target.

AWS credentials are not required when using LocalStack. Dummy credentials defined by the Terraform configuration are used instead.

Ensure LocalStack is running before executing Terraform:

```bash
docker compose up -d
```

The LocalStack endpoint used by Terraform is:

```text
http://localhost:4566
```

### Deploy locally

Initialize Terraform:

```bash
terraform init
```

Review the execution plan:

```bash
make plan
```

Deploy the resources:

```bash
make apply
```

The default target is LocalStack, therefore the following commands are equivalent:

```bash
make plan
make plan TARGET=localstack
```

## AWS deployment

The same Terraform configuration can target a real AWS account.

AWS credentials must be provided through environment variables:

```bash
export AWS_ACCESS_KEY_ID="<access-key>"
export AWS_SECRET_ACCESS_KEY="<secret-key>"
```

When temporary AWS credentials are used, also provide:

```bash
export AWS_SESSION_TOKEN="<session-token>"
```

To generate an AWS execution plan:

```bash
make plan TARGET=aws
```

To deploy:

```bash
make apply TARGET=aws
```

Using `TARGET=aws` disables the LocalStack endpoints and configures the AWS provider to use the standard AWS service endpoints.

AWS deployment must always be explicitly requested. This is intentional to reduce the risk of accidentally creating resources in a real AWS account.

## Makefile

The Makefile provides shortcuts for the most common Terraform operations.

### Format

```bash
make fmt
```

Runs:

```bash
terraform fmt -recursive
```

### Validate

```bash
make validate
```

Validates the Terraform configuration.

### Plan

LocalStack:

```bash
make plan
```

AWS:

```bash
make plan TARGET=aws
```

### Apply

LocalStack:

```bash
make apply
```

AWS:

```bash
make apply TARGET=aws
```

Terraform will request confirmation before applying the changes.

### Destroy

LocalStack:

```bash
make destroy
```

AWS:

```bash
make destroy TARGET=aws
```

Terraform will request confirmation before destroying the resources.

## Configuration

The main Terraform variables are defined in `variables.tf`.

The default configuration targets the local development environment and uses LocalStack-compatible credentials.

Resource names are generated using the project name and environment, for example:

```text
fede-diaz-tech-challenge-dev-users
fede-diaz-tech-challenge-dev-avatars
```

Environment-specific values can be overridden using standard Terraform mechanisms or `TF_VAR_*` environment variables.

## Security

The S3 bucket is private by default. Public ACLs and public bucket policies are blocked.

Server-side encryption using S3-managed keys (`AES256`) is enabled for stored avatars.

No AWS credentials are stored in the repository. When targeting AWS, credentials are provided at runtime through environment variables.

Additional IAM resources required for the Kubernetes workload are handled separately as part of the EKS/Kubernetes integration.