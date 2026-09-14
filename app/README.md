# Prima Tech Challenge Application

This directory contains the Python application used by the Prima Domain SRE Tech Challenge.

The application is a small Flask API backed by AWS DynamoDB and S3:

- **DynamoDB** stores user information.
- **S3** stores user avatars.
- **Gunicorn** is used as the application server when running the container.
- **Swagger UI** provides interactive API documentation.

The application supports both real AWS services and LocalStack for local development and testing.

## Directory Structure

```text
app/
├── prima-tech-challenge/
│   ├── app.py
│   ├── config.py
│   ├── static/
│   │   └── swagger.json
│   └── user_management/
├── tests/
├── Dockerfile
├── Makefile
├── pyproject.toml
├── poetry.lock
└── version.txt
```

## API Endpoints

The application exposes the following endpoints.

### `GET /users`

Returns all users stored in DynamoDB.

Example:

```bash
curl http://localhost:5000/users
```

An empty table returns:

```json
[]
```

### `POST /user`

Creates a new user and uploads the provided avatar to S3.

The request must use `multipart/form-data` and contain:

- `name`
- `email`
- `avatar`

Example:

```bash
curl -X POST http://localhost:5000/user \
  -F "name=Test User" \
  -F "email=test@example.com" \
  -F "avatar=@avatar.png"
```

Allowed avatar extensions are:

```text
png
jpg
jpeg
gif
```

The avatar filename is sanitized before being uploaded.

### `GET /health`

Provides a lightweight application health endpoint.

```bash
curl http://localhost:5000/health
```

Expected response:

```json
{
  "status": "ok"
}
```

This endpoint is also used by the Kubernetes liveness and readiness probes.

### `GET /swagger`

Exposes the Swagger UI for interactive API documentation and testing.

Open:

```text
http://localhost:5000/swagger
```

## Configuration

Application configuration is provided through environment variables.

### Required variables

```text
DYNAMODB_TABLE
S3_BUCKET
```

The AWS region can optionally be configured with:

```text
AWS_REGION
```

and defaults to:

```text
eu-west-1
```

### LocalStack

For local development, configure:

```text
LOCALSTACK_HOST=http://localhost:4566
```

When `LOCALSTACK_HOST` is set, the application uses development AWS credentials automatically.

A typical local `.env` file is:

```dotenv
DYNAMODB_TABLE=fede-diaz-tech-challenge-dev-users
S3_BUCKET=fede-diaz-tech-challenge-dev-avatars
AWS_REGION=eu-west-1
LOCALSTACK_HOST=http://localhost:4566
```

When the application runs inside a Docker container while LocalStack runs on the host, `LOCALSTACK_HOST` must point to an address reachable from the container rather than its own `localhost`.

The repository Docker Compose configuration should be used to start the local LocalStack environment.

### AWS

When using a real AWS account outside EKS, standard AWS credentials can be supplied through:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

and, when temporary credentials are used:

```text
AWS_SESSION_TOKEN
```

Credentials must not be committed to the repository.

For an EKS deployment, static AWS credentials are not required. The Helm ServiceAccount can use the IAM role created by Terraform through IRSA.

See the Terraform documentation for the IAM/IRSA configuration.

## Running Locally with Poetry

The application uses Poetry for dependency management.

Install the dependencies:

```bash
poetry install --no-root
```

Run the Flask development server:

```bash
cd prima-tech-challenge
poetry run flask run
```

The API is then available at:

```text
http://localhost:5000
```

The Flask development server is intended only for local development.

The Docker image uses Gunicorn instead.

## Docker

The application includes a Dockerfile suitable for running the API with Gunicorn.

### Build

The application Makefile provides the Docker lifecycle commands.

```bash
make build
```

The image version is read from:

```text
version.txt
```

For example:

```text
0.1.0
```

### Run

Create the local environment file with the required configuration and run:

```bash
make run
```

The Makefile exposes the application on the configured host port and passes the runtime configuration to the container.

Check the application:

```bash
curl http://localhost:5000/health
```

Expected response:

```json
{"status":"ok"}
```

### Remove

Stop and remove the application container with:

```bash
make rm
```

## Container Runtime

The production container starts the application using Gunicorn rather than the Flask development server.

The application listens on:

```text
0.0.0.0:5000
```

The container also runs as an unprivileged user instead of `root`.

These choices keep development and runtime concerns separated while providing a more appropriate application server for container and Kubernetes deployments.

## Tests

The application includes a small pytest unit test suite covering the core application behavior.

The current tests validate:

- the `/health` endpoint;
- valid user data;
- rejection of missing required fields;
- allowed and disallowed avatar extensions.

Run the tests with:

```bash
make python-test
```

or directly:

```bash
PYTHONPATH=prima-tech-challenge poetry run pytest
```

The application source directory is added to `PYTHONPATH` because the original challenge starter uses a non-package source layout.

## Code Quality

Black and Flake8 are used for formatting and static style checks.

The application Makefile exposes the corresponding checks so they can be run locally before pushing changes.

The repository-level CI executes the same Makefile targets used locally. This avoids maintaining separate validation logic for developers and GitHub Actions.

From the repository root, the complete project validation can be executed with:

```bash
make check
```

This validates the Python application together with Terraform, Helm and the Docker build.

## AWS Access Model

The application uses `boto3` to communicate with S3 and DynamoDB.

The authentication mechanism depends on the environment:

```text
Local development
    |
    +-- LocalStack
        +-- development credentials

Standalone AWS execution
    |
    +-- AWS environment credentials

EKS
    |
    +-- Kubernetes ServiceAccount
        |
        +-- IRSA
            |
            +-- IAM Role
                |
                +-- S3
                +-- DynamoDB
```

The application itself does not contain EKS-specific authentication logic.

When deployed to EKS, the AWS SDK automatically obtains temporary credentials through the ServiceAccount identity provided by IRSA.

This avoids storing long-lived AWS access keys in Kubernetes manifests or application configuration.

## CI/CD

Application changes are validated by GitHub Actions.

The CI pipeline checks:

- Black formatting;
- Flake8;
- pytest;
- Docker image build.

The repository also builds the application image and publishes versioned images to GitHub Container Registry.

Image versions are derived from:

```text
app/version.txt
```

For example:

```text
ghcr.io/nordri/prima-sre-tech-challenge:0.1.0
```

The same image can then be deployed using the Helm chart included in the repository.

## Local End-to-End Testing

For a complete local environment:

1. Start LocalStack using the repository Docker Compose configuration.
2. Deploy the S3 and DynamoDB resources using Terraform.
3. Start the application container.
4. Verify `/health`.
5. Verify `/users`.
6. Create a user through `POST /user`.
7. Verify that the user is stored in DynamoDB and the avatar is uploaded to S3.

The same application image and Helm chart have also been validated in Kubernetes against LocalStack, providing an end-to-end test of the containerized application and its AWS integrations.
