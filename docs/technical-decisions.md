# Technical Decisions

This document describes the main technical decisions made while implementing the Prima Domain SRE Tech Challenge.

The goal is not to describe every implementation detail, but to document the reasoning behind the choices that affect architecture, reliability, security, maintainability and developer experience.

---

## 1. Terraform as Infrastructure as Code

### Decision

Use **Terraform** to provision the AWS infrastructure.

### Rationale

The challenge allows either Terraform or Pulumi.

Terraform was selected because it provides a simple and well-understood way to model the required S3, DynamoDB and IAM resources while keeping the infrastructure implementation declarative and easy to review.

It also allowed the same infrastructure definitions to be exercised against LocalStack and AWS without introducing an additional abstraction layer.

### Trade-offs

Pulumi could provide stronger integration with a general-purpose programming language and may be useful for infrastructure requiring more complex application logic.

For the scope of this challenge, Terraform keeps the infrastructure concise and reduces unnecessary complexity.

---

## 2. LocalStack as the Local AWS Environment

### Decision

Use **LocalStack Community Edition** to run S3 and DynamoDB locally.

### Rationale

The application requires AWS services, but access to a real AWS account should not be necessary to develop or validate the solution.

LocalStack provides a lightweight environment where:

- Terraform can provision the required resources.
- The application can communicate with S3 and DynamoDB.
- The Kubernetes deployment can be tested against AWS-compatible endpoints.

This allows most of the solution to be validated end-to-end without provisioning cloud infrastructure.

### Trade-offs

LocalStack is not AWS.

It is suitable for validating resource definitions and application integration, but it cannot reproduce every AWS or EKS behavior.

AWS-specific features such as EKS OIDC authentication and IRSA therefore remain represented in Terraform but are not artificially emulated in the local environment.

---

## 3. Optional IRSA Resources

### Decision

Make the IAM resources required for **IAM Roles for Service Accounts (IRSA)** optional in Terraform.

IRSA is disabled by default:

```text
enable_irsa = false
```

### Rationale

IRSA requires an existing EKS cluster and OIDC provider.

Neither exists when deploying the solution against LocalStack or a generic Kubernetes cluster such as the environment used for local validation.

Making IRSA optional allows the same Terraform codebase to support:

```text
LocalStack
    |
    +-- S3
    +-- DynamoDB

AWS / EKS
    |
    +-- S3
    +-- DynamoDB
    +-- IAM Policy
    +-- IAM Role
    +-- OIDC trust
```

without creating fake IAM infrastructure solely to satisfy the local environment.

### Trade-offs

The complete IRSA authentication flow cannot be validated without an EKS environment.

The Terraform configuration and resulting trust policy can still be statically validated and inspected using `terraform plan`.

---

## 4. Least-Privilege IAM

### Decision

Grant the application only the AWS actions currently required by its implementation.

The IAM policy allows:

```text
dynamodb:Scan
dynamodb:PutItem
s3:PutObject
```

and restricts these permissions to the application DynamoDB table and S3 bucket.

### Rationale

The application should not require broad permissions such as:

```text
dynamodb:*
s3:*
```

Limiting permissions reduces the impact of application compromise or accidental misuse.

The IRSA trust relationship is also restricted to a specific Kubernetes identity:

```text
system:serviceaccount:<namespace>:<service-account>
```

### Trade-offs

New application functionality that requires additional AWS operations will require an explicit IAM policy change.

This is intentional: infrastructure permissions should evolve together with application requirements.

---

## 5. No Static AWS Credentials in Kubernetes

### Decision

Use IRSA as the intended authentication mechanism for EKS instead of injecting long-lived AWS credentials into application pods.

### Rationale

Static credentials would require storing and distributing:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

through Kubernetes configuration or Secrets.

With IRSA, the application can use the standard AWS SDK credential chain and obtain temporary credentials through AWS STS.

This removes long-lived AWS credentials from:

- container images;
- Helm values;
- Kubernetes manifests;
- application configuration.

### Trade-offs

IRSA introduces a dependency on EKS OIDC configuration and requires coordination between IAM and Kubernetes ServiceAccounts.

The additional infrastructure complexity is justified for an AWS/EKS production environment.

---

## 6. Keep AWS IAM Logic Out of the Helm Chart

### Decision

Keep the Helm chart unaware of IRSA-specific implementation details.

The chart supports generic ServiceAccount annotations:

```yaml
serviceAccount:
  annotations: {}
```

For EKS, the Terraform-created role can be supplied as:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <iam-role-arn>
```

### Rationale

Terraform owns AWS infrastructure and IAM.

Helm owns Kubernetes resources.

Keeping this boundary avoids coupling the Kubernetes chart to the mechanism used to provision AWS identities.

It also means the same chart can be used in environments where IRSA does not exist.

### Trade-offs

The IAM role ARN must be passed from the infrastructure deployment to the Helm deployment.

In a larger delivery platform this hand-off would normally be automated by the deployment pipeline or GitOps configuration.

---

## 7. Runtime Configuration Instead of Image Configuration

### Decision

Provide environment-specific configuration when the container starts rather than embedding it in the Docker image.

Examples include:

```text
DYNAMODB_TABLE
S3_BUCKET
AWS_REGION
LOCALSTACK_HOST
```

### Rationale

The same container image should be deployable to different environments.

Building separate images for LocalStack, development and production would couple configuration to the build process and make artifact promotion more difficult.

The resulting model is:

```text
                  Same image
                      |
          +-----------+-----------+
          |                       |
          v                       v
       Local                    EKS
          |                       |
     LocalStack               AWS services
```

### Trade-offs

Runtime configuration must be correctly supplied by the deployment environment.

Configuration validation therefore becomes important when the application starts.

---

## 8. Gunicorn Instead of the Flask Development Server

### Decision

Run the containerized application using **Gunicorn**.

### Rationale

`flask run` is intended for application development.

The container should use an application server appropriate for a deployed environment while keeping Flask responsible for the application itself.

Gunicorn provides this with little additional complexity.

### Trade-offs

Worker count, worker type, timeouts and other Gunicorn parameters would require tuning for real production traffic.

The challenge uses a simple configuration rather than attempting to tune values without workload data.

---

## 9. Run the Container as a Non-Root User

### Decision

Run the application process as an unprivileged user inside the container.

### Rationale

The application does not require root privileges.

Removing unnecessary privileges reduces the impact of a potential application or dependency compromise and provides a safer default for Kubernetes deployment.

### Trade-offs

Files and directories required by the application must have appropriate ownership and permissions during image creation.

For this application the additional complexity is minimal.

---

## 10. Lightweight Application Health Check

### Decision

Expose:

```text
GET /health
```

and use it for Kubernetes liveness and readiness probes.

The endpoint verifies application availability but does not query DynamoDB or S3.

### Rationale

A health check used for liveness should primarily answer:

> Can this application process serve requests?

If the health endpoint depended on DynamoDB or S3, an AWS service failure could cause Kubernetes to restart otherwise healthy application processes.

That would not repair the downstream dependency and could amplify an existing incident.

### Trade-offs

`/health` does not prove that every application dependency is operational.

Dependency health should instead be observed separately through application metrics, request failures and appropriate monitoring.

A more complex production environment could also expose separate liveness and readiness semantics if required.

---

## 11. CPU-Based Horizontal Pod Autoscaling

### Decision

Provide a Kubernetes HorizontalPodAutoscaler using CPU utilization with:

```text
minReplicas: 2
maxReplicas: 5
target CPU utilization: 70%
```

### Rationale

CPU provides a simple baseline metric supported by standard Kubernetes HPA behavior.

A minimum of two replicas also avoids depending on a single application instance during normal operation.

### Trade-offs

CPU utilization is not necessarily the best scaling signal for this application.

A production implementation should select scaling metrics based on observed workload behavior, for example:

- request rate;
- request latency;
- queue depth;
- application-specific workload metrics.

No custom scaling metric was introduced because there is no workload data demonstrating that it would be more appropriate.

---

## 12. No Unnecessary Kubernetes Resources

### Decision

Do not add resources such as PDBs, NetworkPolicies, Ingress controllers, service meshes or topology constraints solely to make the solution appear more production-like.

### Rationale

These resources solve real problems, but their correct configuration depends on requirements that are not defined by the challenge.

For example:

- a PDB depends on availability and maintenance requirements;
- NetworkPolicies depend on the CNI and expected traffic flows;
- topology spread depends on cluster topology;
- Ingress depends on networking, DNS and TLS architecture.

Adding arbitrary configurations without those requirements would create the appearance of completeness without demonstrating a justified engineering decision.

### Trade-offs

A real production deployment would likely require some of these mechanisms once its availability, networking and security requirements are known.

---

## 13. Public Avatar Access Through S3 Bucket Policy

### Decision

Allow public avatar reads through an S3 bucket policy while keeping public object ACLs disabled.

### Rationale

The application returns avatar URLs that need to be directly accessible.

Centralizing public-read behavior in the bucket policy avoids assigning `public-read` ACL ownership independently to uploaded objects.

Public ACLs are therefore blocked while the required public access is explicitly defined at bucket level.

### Trade-offs

A public S3 bucket is appropriate for the behavior required by the current application, but it would not necessarily be the preferred architecture for private or controlled user content.

A production system with different requirements could instead use CloudFront, signed URLs or authenticated application access.

---

## 14. Makefile as the Common Validation Interface

### Decision

Use Makefile targets as the common interface for local development and CI validation.

For example:

```bash
make python-check
make terraform-check
make helm-check
make docker-check
make check
```

### Rationale

CI should not contain a second implementation of the project's validation process.

GitHub Actions executes the same commands developers can run locally.

This provides:

```text
Developer
    |
    +------ make check
                |
                +-- Python
                +-- Terraform
                +-- Helm
                +-- Docker

GitHub Actions
    |
    +------ make <target>
                |
                +-- same validation
```

This improves reproducibility and makes CI failures easier to reproduce locally.

### Trade-offs

The Makefile becomes part of the project's development interface and must be maintained when validation steps change.

That is preferable to maintaining duplicated shell commands across local documentation and CI workflows.

---

## 15. Separate CI Validation Jobs

### Decision

Run Python, Terraform, Helm and Docker validation as separate GitHub Actions jobs.

### Rationale

The components are largely independent.

Running them separately:

- provides faster feedback;
- makes failures easier to identify;
- allows independent execution;
- allows GitHub Actions to execute checks concurrently.

### Trade-offs

Separate jobs repeat some runner initialization overhead.

For a repository of this size, clearer feedback and parallelism are more valuable than minimizing runner startup time.

---

## 16. Versioned Container Images

### Decision

Store the application version in:

```text
app/version.txt
```

and use that version when publishing the container image.

Images are published using both a versioned tag and `latest`.

Example:

```text
ghcr.io/nordri/prima-sre-tech-challenge:0.1.0
ghcr.io/nordri/prima-sre-tech-challenge:latest
```

### Rationale

Kubernetes deployments should be able to reference an immutable application version rather than relying exclusively on a mutable tag.

Keeping the version in the application directory also makes the intended release version visible without depending on CI implementation details.

### Trade-offs

Version management is currently manual.

A larger project could derive versions from Git tags or an automated release process.

---

## 17. Small, Focused Unit Test Suite

### Decision

Add a small pytest suite focused on important application behavior rather than attempting to achieve high coverage for its own sake.

The initial tests cover:

- application health;
- required user fields;
- valid user input;
- allowed avatar extensions.

### Rationale

The challenge is primarily focused on SRE and infrastructure concerns.

A small suite provides regression protection for the application changes introduced during the exercise while keeping effort proportional to the size of the application.

AWS integration has additionally been exercised using LocalStack rather than replacing all AWS interactions with mocks.

### Trade-offs

The current suite does not comprehensively cover application behavior or failure modes.

A production application should add tests based on risk, including API behavior, AWS failures and integration scenarios.

---

## 18. No Real EKS Cluster for Validation

### Decision

Do not provision an EKS cluster solely to validate the challenge.

### Rationale

The exercise explicitly does not require a running EKS cluster.

The solution instead validates different concerns at the most appropriate level:

```text
Application logic       -> pytest
Container               -> Docker
AWS resources           -> Terraform + LocalStack
AWS integration         -> LocalStack
Kubernetes manifests    -> Helm lint/template
Kubernetes runtime      -> KillerCoda
EKS IAM design          -> Terraform IRSA configuration
```

This provides meaningful validation without introducing the cost and complexity of an EKS cluster that is not required by the exercise.

### Trade-offs

EKS-specific runtime behavior, particularly the complete IRSA token exchange, cannot be demonstrated without a real EKS environment.

The implementation nevertheless contains the required IAM/OIDC configuration and keeps the EKS-specific boundary explicit.

---

## Summary

The overall implementation favors:

- reproducibility over environment-specific manual steps;
- least privilege over broad permissions;
- runtime configuration over environment-specific artifacts;
- explicit boundaries between Terraform, Helm and application concerns;
- meaningful local validation over unnecessary cloud resources;
- simple, justified components over speculative production complexity.

The solution is intentionally designed as a solid baseline that can evolve once real production requirements such as traffic patterns, availability targets, observability requirements and deployment policies are known.
