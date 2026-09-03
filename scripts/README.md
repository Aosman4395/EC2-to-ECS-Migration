# Validation Scripts

These scripts automate local validation of the containerised legacy API before the Docker image progresses to Amazon ECR and ECS.

## `test-container.sh`

This script orchestrates the local Docker validation workflow.

It:

1. Builds the `legacy-app:test` Docker image.
2. Starts a container named `legacy-test` and maps port `5000` on the host to port `5000` in the container.
3. Polls the `/health` endpoint, retrying while the application starts.
4. Runs `test-api.sh` once the container is healthy.
5. Stops and removes the test container after successful validation.

The Docker image is intentionally retained after testing so that the validated image can later be tagged and pushed to Amazon ECR.

## `test-api.sh`

This script runs API endpoint tests against the running application.

The validation covers:

- Health endpoint
- Product listing
- Individual product retrieval
- Expected `404` responses
- Order creation
- Order retrieval
- Invalid product orders
- Missing required order data and expected `400` responses
- Statistics endpoint

Each endpoint is checked against its expected HTTP status code. If an endpoint returns an unexpected status, the test fails with a non-zero exit code.

## How the Scripts Work Together

The normal local validation flow is:

```text
test-container.sh
      |
      v
Build Docker image
      |
      v
Start test container
      |
      v
Wait for /health
      |
      v
Run test-api.sh
      |
      v
Validate API endpoints
      |
      v
Stop and remove test container
      |
      v
Keep validated Docker image
```

`test-container.sh` automatically invokes `test-api.sh`, so the API test script does not need to be started manually during the normal container validation workflow.

## Usage

Run the complete validation workflow from the repository root:

```bash
./scripts/test-container.sh
```

The API tests can also be run independently against a running local container:

```bash
./scripts/test-api.sh http://localhost:5000
```

The same API test script can later be reused against other deployment URLs, allowing the application behaviour to be validated as the migration progresses from local Docker to ECS.