# EC2 to ECS Fargate Migration

## Overview

This project migrates a legacy Python/Flask ordering API from a single Amazon EC2 instance to a containerised Amazon ECS Fargate platform.

The migration is being completed incrementally so the original workload can be understood, tested and compared directly with the new platform before traffic is cut over.

**EC2 baseline → Docker → RDS persistence → ECS Fargate → CI/CD → validation → cutover**

The project is documented in three main sections:

1. [Legacy EC2 Environment](#1-legacy-ec2-environment)
2. [ECS Fargate Migration Environment](#2-ecs-fargate-migration-environment)
3. [CI/CD, Security and Validation](#3-cicd-security-and-validation)

Test evidence is stored separately under [`tests/`](tests/README.md).

---

# 1. Legacy EC2 Environment

## Legacy Architecture

```text
Client
  |
  v
EC2
  |
  v
Nginx :80
  |
  v
Gunicorn :5000
  |
  v
Flask API
  |
  v
Python in-memory storage
```

The inherited application is a Flask API served by Gunicorn behind Nginx.

### API endpoints

- `GET /health`
- `GET /ready`
- `GET /api/v1/products`
- `GET /api/v1/products/{id}`
- `POST /api/v1/orders`
- `GET /api/v1/orders`
- `GET /api/v1/stats`

## Legacy Infrastructure

The EC2 environment is provisioned with Terraform and includes:

- VPC and public subnet
- Internet Gateway and routing
- EC2 instance
- Security group
- Elastic/public IPv4 connectivity
- Nginx reverse proxy
- Gunicorn application service
- S3 application package used during provisioning

The application package hash is included in EC2 user data so application changes can trigger instance replacement when required.

## Legacy Storage Backend

The original application keeps products, stock and orders in Python memory.

The shared application code now selects its storage implementation through an environment variable:

```text
STORAGE_BACKEND=memory
```

This lets the EC2 environment keep the original legacy behaviour while the ECS environment uses PostgreSQL.

### Legacy environment variables

```text
APP_NAME=legacy-api
APP_VERSION=1.0.0
ENVIRONMENT=production
STORAGE_BACKEND=memory
```

No RDS credentials are required by the EC2 workload.

## Legacy Limitations Identified

- **Single point of failure** — one EC2 instance hosts the application.
- **No autoscaling** — capacity cannot respond automatically to demand.
- **Manual/server-based deployments** — application releases are tied to the host.
- **Limited observability** — logs and operational visibility are tied to the instance.
- **In-memory state** — orders and stock changes are not durable.
- **Gunicorn worker inconsistency** — separate worker processes can hold different copies of application state.
- **Restart data loss** — restarting the application or EC2 instance resets orders and stock.

Baseline testing confirmed the API worked correctly before migration. Testing also demonstrated the in-memory limitation: after creating an order, restarting EC2 removed the order and returned Widget A stock to its original value.

---

# 2. ECS Fargate Migration Environment

## Target / Staging Architecture

```text
                         Internet
                            |
                            v
                 Application Load Balancer
                         HTTP :80
                            |
                            v
                    ECS Fargate Service
                            |
                            v
                       Flask API
                            |
                            v
                     RDS PostgreSQL
                            ^
                            |
                    Secrets Manager
```

The staging environment currently uses HTTP intentionally while the migration platform is validated. Production HTTPS/ACM and final traffic cutover will be introduced later.

## Containerisation

The Flask application was containerised before ECS deployment.

The Docker image:

- Uses `python:3.9-slim`
- Installs dependencies from `requirements.txt`
- Runs Gunicorn on port `5000`
- Runs as a dedicated non-root user
- Uses `.dockerignore` to reduce unnecessary build context
- Contains the API, storage implementations, `schema.sql` and `init_db.py`

The image is stored in Amazon ECR using immutable image tags.

## Shared Application / Pluggable Storage

Instead of maintaining separate EC2 and ECS versions of the API, both environments use the same `app.py` and select a storage backend at runtime.

```text
                    app.py
                      |
               STORAGE_BACKEND
                 /         \
                /           \
             memory       postgres
               |             |
              EC2           RDS
```

`storage/__init__.py` selects either:

- `MemoryStorage`
- `PostgresStorage`

There is deliberately **no silent PostgreSQL-to-memory fallback**. If the ECS PostgreSQL backend is unavailable, the application should expose the failure rather than run with non-persistent state.

## ECS Environment Variables

The ECS task uses:

```text
STORAGE_BACKEND=postgres
DB_HOST=<RDS endpoint>
DB_PORT=5432
DB_NAME=migrationdb
DB_USER=<injected from Secrets Manager>
DB_PASSWORD=<injected from Secrets Manager>
DB_SSLMODE=require
```

The database username and password are injected at task startup from AWS Secrets Manager rather than being hardcoded in Terraform or the container image.

## Networking

The staging VPC contains:

- 2 public subnets for internet-facing infrastructure
- 2 private ECS subnets
- 2 private RDS subnets
- Internet Gateway
- NAT Gateway for ECS private-subnet egress
- Separate security groups for the ALB, ECS and RDS

Traffic flow:

```text
Internet
   |
   v
ALB :80
   |
   v
ECS task :5000
   |
   v
RDS PostgreSQL :5432
```

RDS only permits PostgreSQL traffic from the ECS task security group. RDS is not publicly exposed.

## RDS PostgreSQL

Terraform provisions PostgreSQL with:

```text
Database: migrationdb
Master user: migrationuser
Storage: 20 GiB
Instance class: db.t3.micro
Credentials: RDS-managed Secrets Manager secret
```

Automatic master-password rotation is currently disabled in staging because ECS environment-variable secrets are loaded when a task starts. This avoids a running task retaining an older password after an automatic rotation. A production rotation/redeployment strategy can be added later.

## Manual Database Initialisation

Terraform provisions the database server and database, but application tables are deliberately initialised separately.

The existing application image was run as a **temporary one-off ECS task** with its normal Gunicorn command overridden by:

```bash
python init_db.py
```

The task reused the existing ECS task definition, private subnets, ECS security group, RDS endpoint and Secrets Manager credentials.

The flow was:

```text
Terraform creates RDS
        |
        v
Database exists but application tables do not
        |
        v
Run temporary ECS task using application image
        |
        v
Override command -> python init_db.py
        |
        v
Connect privately to RDS using injected credentials
        |
        v
Execute schema.sql
        |
        v
Create products + orders tables
        |
        v
Seed Widget A / B / C
        |
        v
Run storage readiness check
        |
        v
Database schema and sample products are ready
```

`schema.sql` uses `CREATE TABLE IF NOT EXISTS` and `ON CONFLICT DO NOTHING`, allowing the initial setup command to be rerun without deleting existing orders or resetting existing product rows.

The temporary setup task exits after initialisation. The normal ECS service continues to start with Gunicorn.

## Health and Readiness

The application separates process health from storage readiness:

```text
/health -> Flask/Gunicorn process is alive
/ready  -> selected storage backend is accessible
```

For ECS, a successful readiness response is:

```json
{"status":"ready","storage":"postgres"}
```

The ALB health check remains `/health`; `/ready` is used for application/database validation.

## Persistence Validation

ECS testing confirmed:

- Health endpoint works through the ALB.
- PostgreSQL readiness succeeds.
- Three seeded products can be read from RDS.
- Orders can be created through the API.
- Product stock is updated transactionally.
- Statistics reflect persisted order data.
- Data survives ECS task replacement.

A test order for two units of Widget A produced:

```text
Orders:        1
Widget A:      stock 100 -> 98
Total revenue: 59.98
```

After forcing a new ECS deployment, those values remained unchanged, confirming that application state is persisted in RDS rather than inside the container.

---

# 3. CI/CD, Security and Validation

## GitHub Actions Deployment Flow

The staging delivery process uses two connected GitHub Actions workflows:

```text
Push to main
    |
    v
Detect changed files
    |
    +-------------------------------+
    |                               |
App change                      Infra-only change
    |                               |
    v                               v
Build Docker image              Skip image build
    |
    v
Trivy scan
    |
    v
Push immutable image to ECR
    |                               |
    +---------------+---------------+
                    |
                    v
          Call staging Terraform workflow
                    |
                    v
                 Checkov
                    |
                    v
             terraform fmt
                    |
                    v
             terraform init
                    |
                    v
           terraform validate
                    |
                    v
             terraform plan
                    |
                    v
        Upload saved Terraform plan
                    |
                    v
        GitHub Environment approval
                    |
                    v
             terraform apply
```

### Change-aware image deployment

Application changes build a new image and pass the **exact immutable image URI** into the reusable staging Terraform workflow.

Image tags use:

```text
<commit-sha>-<workflow-run-id>-<run-attempt>
```

This avoids collisions with immutable ECR tags and makes each deployed image traceable to a specific GitHub commit and workflow execution.

For infrastructure-only changes, the build job is skipped. The staging workflow reads the image currently used by the ECS service and retains that exact image during Terraform deployment rather than selecting an arbitrary latest ECR image.

This provides deterministic deployments while avoiding unnecessary Docker builds.

## CI/CD Security Controls

Current controls include:

- GitHub Actions → AWS authentication using **OIDC** instead of stored long-lived AWS access keys
- **Trivy** container image scanning
- **Checkov** Terraform scanning
- Docker container runs as a **non-root user**
- ECS tasks deployed in **private subnets**
- RDS deployed in **private subnets**
- Security-group restricted ECS → RDS access on port `5432`
- Database credentials stored in **AWS Secrets Manager**
- ECR **immutable image tags**
- ECR image scanning enabled
- Terraform remote state stored in S3
- GitHub **Migration environment approval** before Terraform apply
- Saved Terraform plan is applied after approval so the reviewed plan is the one deployed
- Workflow concurrency prevents overlapping staging Terraform deployments

## Validation Completed

The current migration has successfully validated both sides of the comparison:

| Validation | Legacy EC2 | ECS Fargate + RDS |
| --- | --- | --- |
| Process health | ✅ | ✅ |
| Storage readiness | ✅ memory | ✅ postgres |
| Read products | ✅ | ✅ |
| Create order | ✅ | ✅ |
| Update stock | ✅ | ✅ |
| Stats endpoint | ✅ | ✅ |
| Survives compute restart/replacement | ❌ | ✅ |
| Shared persistent storage | ❌ | ✅ |
| Private database | N/A | ✅ |
| Automated image/infrastructure pipeline | ❌ | ✅ |

The evidence for these tests is documented in [`tests/README.md`](tests/README.md).

## Current Migration Status

The staging platform is now functionally validated:

```text
Legacy EC2                ECS migration platform
-----------               ----------------------
Nginx                     Application Load Balancer
Gunicorn                  ECS Fargate
Flask API                 Same Flask API
Memory storage      ->    RDS PostgreSQL
Host-bound state          Persistent shared state
Manual/server model       Automated CI/CD model
```

The next major phase is the **controlled EC2 → ECS traffic cutover and rollback strategy**. The legacy EC2 environment will remain available during the rollback window until the ECS platform is considered stable.
