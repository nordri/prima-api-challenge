# Helm Deployment

This directory contains the Helm chart used to deploy the Prima Tech Challenge API to Kubernetes.

## Resources

The chart creates:

- Deployment
- Service
- ServiceAccount
- HorizontalPodAutoscaler

The Deployment includes:

- CPU and memory requests/limits
- Liveness probe
- Readiness probe
- Runtime configuration through environment variables

## Requirements

- Kubernetes cluster
- Helm 3
- Container image available from a registry

## Validate the chart

From the repository root:

```bash
helm lint ./helm/prima-tech-challenge
helm template prima ./helm/prima-tech-challenge
```

The same validation is executed by CI through:

```bash
make helm-check
```

## Install

Example deployment:

```
helm install prima ./helm/prima-tech-challenge \
  --set image.repository=ghcr.io/nordri/prima-sre-tech-challenge \
  --set image.tag=0.1.0
  ```

Check the deployment:

```
kubectl get pods
kubectl get deploy
kubectl get svc
kubectl get hpa
```

## Application configuration

The following values configure the AWS resources used by the application:

```
env:
  dynamodbTable: fede-diaz-tech-challenge-dev-users
  s3Bucket: fede-diaz-tech-challenge-dev-avatars
  awsRegion: eu-west-1
  localstackHost: ""
```

For an AWS/EKS deployment, localstackHost should remain empty.

For a local Kubernetes environment using LocalStack, provide an endpoint reachable from the application pods:

```
helm install prima ./helm/prima-tech-challenge \
  --set image.repository=ghcr.io/nordri/prima-sre-tech-challenge \
  --set image.tag=0.1.0 \
  --set env.localstackHost=http://<localstack-host>:4566
```

## Health checks

The application exposes:

`GET /health`

Both liveness and readiness probes use this endpoint.

The health endpoint checks application process availability and deliberately does not query external dependencies such as S3 or DynamoDB. This avoids restarting healthy application pods during downstream AWS service failures.

## Autoscaling

The chart creates an HPA using CPU utilization.

Default configuration:

```
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
```

The HPA requires a Kubernetes Metrics API implementation such as metrics-server.

During validation in KillerCoda the Metrics API was not available, therefore the HPA resource was created successfully but reported CPU metrics as unknown.

## ServiceAccount and IRSA

The chart creates a Kubernetes ServiceAccount.

Annotations can be supplied through:

```
serviceAccount:
  annotations: {}
```

For EKS, the IAM role created by Terraform can be attached using:

```
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <terraform-irsa-role-arn>
```

The chart intentionally contains no AWS-specific IAM resources. IAM configuration is managed by Terraform while Helm only consumes the resulting role ARN.

## Local validation

The chart was validated in KillerCoda using:

- The application image published to GHCR
- LocalStack running S3 and DynamoDB
- Terraform-provisioned resources
- Two application replicas

The following paths were successfully tested:

- `GET /health`
- `GET /users`

The deployment reached:

- `2/2` pods Ready
- Deployment Available
- Service reachable through port-forward

Example port-forward:

```
kubectl port-forward svc/prima 8080:5000
```

Then:

```
curl http://localhost:8080/health
curl http://localhost:8080/users
```
