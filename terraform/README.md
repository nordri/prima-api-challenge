# Terraform Infrastructure

This directory contains the Terraform configuration required by the Prima Tech Challenge application.

The infrastructure can be deployed against either:

- **LocalStack**, for local development and testing.
- **AWS**, for a real deployment.

When running on EKS, the configuration can optionally create the IAM resources required for **IAM Roles for Service Accounts (IRSA)**.

## Resources

The Terraform configuration creates the following application resources:

- An **S3 bucket** used to store user avatars.
- Server-side encryption for the S3 bucket.
- S3 public access configuration and bucket policy required to expose uploaded avatars.
- A **DynamoDB table** used to store users.

When IRSA is enabled, Terraform additionally creates:

- An IAM policy containing the permissions required by the application.
- An IAM role that can be assumed through the EKS OIDC provider.
- An IAM policy attachment associating the application policy with the role.

## Directory Structure

```text
terraform/
├── backend.tf
├── variables.tf
├── locals.tf
├── providers.tf
├── s3.tf
├── dynamodb.tf
├── iam.tf
├── outputs.tf
├── Makefile
└── README.md
```

## Requirements

The following tools are required:

- Terraform `1.15.9`
- AWS CLI
- LocalStack for local development

Terraform can optionally be installed using `tfswitch`.

```bash
curl -L https://raw.githubusercontent.com/warrensbox/terraform-switcher/master/install.sh | bash
tfswitch 1.15.9
```

## LocalStack

LocalStack is the default development environment.

The Terraform configuration is designed so that IAM/IRSA resources are **not created by default**, allowing the application infrastructure to be deployed without requiring an EKS cluster or OIDC provider.

A Docker Compose configuration is provided in the repository:

```text
docker-compose/
└── compose.yaml
```

Start LocalStack from the repository root:

```bash
docker compose -f docker-compose/compose.yaml up -d
```

Verify that the container is running:

```bash
docker compose -f docker-compose/compose.yaml ps
```

LocalStack can also be checked directly through its health endpoint:

```bash
curl http://localhost:4566/_localstack/health
```

The S3 and DynamoDB services should report a running state.

To stop the local environment:

```bash
docker compose -f docker-compose/compose.yaml down
```

LocalStack exposes its AWS API endpoint on:

```text
http://localhost:4566
```
## Makefile

A Makefile is provided for the common Terraform lifecycle operations.

### Format

```bash
make fomat
```

Formats the Terraform configuration.

### Validate

```bash
make validate
```

Initializes Terraform and validates the configuration.

### Plan

```bash
make plan
```

Generates a Terraform execution plan.

By default, the Makefile configures Terraform to use LocalStack.

### Apply

```bash
make apply
```

Applies the Terraform configuration:

```text
S3 bucket
DynamoDB table
S3 encryption
S3 public access configuration
S3 bucket policy
```

### Destroy

```bash
make destroy
```

Destroys the resources managed by Terraform.

## AWS Credentials

The Terraform configuration supports both LocalStack credentials and real AWS credentials.

When AWS credentials are available in the environment, they can be provided using the standard variables:

```bash
export AWS_ACCESS_KEY_ID=<access-key>
export AWS_SECRET_ACCESS_KEY=<secret-key>
```

For temporary credentials:

```bash
export AWS_SESSION_TOKEN=<session-token>
```

When running against LocalStack, development credentials are used instead.

Real AWS credentials should never be committed to the repository.

## IAM and IRSA

For an EKS deployment, the application should not use static AWS credentials.

Instead, the Kubernetes ServiceAccount can authenticate to AWS using **IAM Roles for Service Accounts (IRSA)**.

IRSA creation is optional and disabled by default:

```text
enable_irsa = false
```

This keeps the Terraform configuration compatible with LocalStack and Kubernetes development environments such as KillerCoda.

When enabled, Terraform creates an IAM policy containing only the permissions currently required by the application:

### DynamoDB

```text
dynamodb:Scan
dynamodb:PutItem
```

### S3

```text
s3:PutObject
```

The permissions are restricted to the DynamoDB table and S3 bucket created by this Terraform configuration.

## Enabling IRSA

IRSA requires an existing EKS cluster with an IAM OIDC provider.

The following values must be provided:

```text
enable_irsa
eks_oidc_provider_arn
eks_oidc_issuer_url
kubernetes_namespace
kubernetes_service_account
```

The namespace defaults to:

```text
default
```

and the ServiceAccount defaults to:

```text
prima
```

Example:

```bash
TF_VAR_enable_irsa=true \
TF_VAR_eks_oidc_provider_arn="arn:aws:iam::<account-id>:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/<oidc-id>" \
TF_VAR_eks_oidc_issuer_url="https://oidc.eks.eu-west-1.amazonaws.com/id/<oidc-id>" \
terraform plan
```

The IAM role trust policy restricts role assumption to the configured Kubernetes ServiceAccount:

```text
system:serviceaccount:<namespace>:<service-account>
```

and requires the audience:

```text
sts.amazonaws.com
```

The resulting authentication flow is:

```text
Kubernetes Pod
      |
      v
ServiceAccount
      |
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
      +----> DynamoDB
      |
      +----> S3
```

## Connecting IRSA to the Helm Deployment

Terraform exposes the created IAM role ARN:

```bash
terraform output irsa_role_arn
```

The Helm chart supports arbitrary ServiceAccount annotations, so no AWS-specific logic is required in the chart itself.

For an EKS deployment, the Terraform output can be supplied to Helm as:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <irsa-role-arn>
```

or from the command line:

```bash
helm install prima ./helm/prima-tech-challenge \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="<irsa-role-arn>"
```

When running against LocalStack or a local Kubernetes environment, this annotation is simply omitted.

## Local Validation

Start LocalStack from the repository root:

```bash
docker compose -f docker-compose/compose.yaml up -d
```

Then deploy the infrastructure:

```bash
cd terraform

make validate
make plan
make apply
```

The expected Terraform plan creates five resources:

```text
DynamoDB table
S3 bucket
S3 server-side encryption configuration
S3 public access configuration
S3 bucket policy
```

The resulting AWS resources can be verified using the AWS CLI.

### S3

```bash
aws --profile localstack \
  --endpoint-url=http://localhost:4566 \
  s3api list-buckets
```

### DynamoDB

```bash
aws --profile localstack \
  --endpoint-url=http://localhost:4566 \
  dynamodb list-tables
```

The expected resources are:

```text
fede-diaz-tech-challenge-dev-avatars
fede-diaz-tech-challenge-dev-users
```

When finished:

```bash
make destroy

cd ..
docker compose -f docker-compose/compose.yaml down
```

## Design Decisions

### LocalStack support

LocalStack allows the infrastructure and application integration to be tested without requiring access to an AWS account.

The same Terraform resources are used for both environments; only provider configuration and optional AWS-specific resources differ.

### Optional IRSA

IRSA depends on an existing EKS OIDC provider and therefore cannot be meaningfully created in the LocalStack development environment.

For this reason, IRSA resources are explicitly optional rather than being mocked locally.

### Least privilege

The IAM policy grants only the AWS operations currently performed by the application and scopes them to the application resources.

### No static credentials in Kubernetes

A production EKS deployment is expected to use IRSA instead of injecting `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` into the application pods.

This keeps AWS credentials out of Kubernetes manifests and delegates credential rotation to AWS STS.
