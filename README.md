# EC2 to ECS Fargate Migration

## Project Overview

This project migrates a legacy Python/Flask ordering API from a single Amazon EC2 instance to a containerised Amazon ECS Fargate platform backed by Amazon RDS PostgreSQL.

The migration is deliberately split into three environments so the legacy workload can be reproduced first, the new platform can be built and validated alongside it, and production cutover can then be completed with a rollback path available.

```text
DEV / LEGACY EC2  ->  STAGING / ECS + RDS  ->  PROD / CUTOVER
```

### What the API does

The application is a small ordering API containing three sample products. It supports product reads, order creation, stock updates and basic order statistics.

```text
GET  /health
GET  /ready
GET  /api/v1/products
GET  /api/v1/products/{id}
POST /api/v1/orders
GET  /api/v1/orders
GET  /api/v1/stats
```

### Why migrate it?

The legacy application runs on a single EC2 instance behind Nginx and stores its state directly in Python memory. Testing exposed several limitations:

- Single EC2 instance creates a single point of failure.
- No application autoscaling.
- Deployments are tied to the server.
- Orders and stock are stored in memory rather than durable storage.
- Gunicorn workers can hold separate copies of application state.
- Restarting the application or EC2 instance loses order and stock changes.
- Monitoring and logs are tied closely to the host.
- There is no controlled traffic cutover or rollback mechanism.

### Previous architecture

```text
Internet
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
Python memory
```

### Target architecture

```text
Internet
   |
   v
Application Load Balancer
   |
   v
ECS Fargate Service
   |
   v
Flask API
   |
   v
RDS PostgreSQL

Secrets Manager -> ECS database credentials
CloudWatch      -> logs / metrics / alarms
ECR             -> immutable container images
GitHub Actions  -> CI/CD
```

The application code is shared between environments. `STORAGE_BACKEND` selects whether the API uses the original memory implementation or PostgreSQL:

```text
                    app.py
                      |
               STORAGE_BACKEND
                 /         \
              memory      postgres
                |            |
               EC2          RDS
```

There is no automatic PostgreSQL-to-memory fallback. If PostgreSQL is unavailable, the ECS deployment should expose that failure rather than silently return to non-persistent storage.

---

# DEV — Legacy EC2

## Purpose

The dev environment reproduces the original legacy application so its behaviour and limitations can be understood before migration.

It remains the **before state** of the project and later provides the old environment during cutover/rollback testing.

## Architecture

```text
Internet
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
MemoryStorage
```

## Infrastructure completed

Terraform provisions the legacy environment including:

- VPC
- Public subnet
- Internet Gateway and routing
- EC2 instance
- Security group
- Public IPv4 connectivity
- S3 application package
- Nginx reverse proxy
- Gunicorn application service

An application archive hash is included in EC2 user data so application changes can trigger replacement when required.

Terraform state is stored remotely in S3.

## Application configuration

The EC2 deployment uses the shared Flask application with the original memory-backed behaviour:

```text
APP_NAME=legacy-api
APP_VERSION=1.0.0
ENVIRONMENT=production
STORAGE_BACKEND=memory
```

No RDS credentials or database networking are required for the legacy environment.

## What was validated

The API was tested before and after creating an order. Widget A stock changed from `100` to `98` while the application was running.

The EC2 instance was then manually rebooted. After restart the order disappeared and Widget A returned to stock `100`, confirming that the legacy application state is not durable.

Test evidence is kept in [`tests/`](tests/README.md).

---

# STAGING — ECS Fargate Migration

## Purpose

Staging runs the new ECS/RDS architecture alongside the legacy EC2 environment. This allows the migration to be built, deployed and tested without removing the rollback environment.

The current staging application is exposed through an internet-facing ALB over HTTP while the platform is being validated. HTTPS is reserved for the production phase.

## Architecture

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

              Secrets Manager -> ECS Task
```

## Containerisation and ECR

The Flask application was containerised using `python:3.9-slim` and Gunicorn on port `5000`.

The container:

- Runs as a dedicated non-root user.
- Installs dependencies from `requirements.txt`.
- Uses `.dockerignore` to reduce unnecessary build context.
- Contains `app.py`, the storage implementations, `schema.sql` and `init_db.py`.

Amazon ECR was bootstrapped separately with:

- Immutable image tags.
- Image scanning on push.
- S3-backed Terraform state for the main staging infrastructure.

Bootstrap resources are kept separate from normal staging destroy operations.

## Networking

The staging VPC contains:

- 2 public subnets.
- 2 private ECS subnets.
- 2 private RDS subnets.
- Internet Gateway.
- NAT Gateway for private ECS egress.
- Separate ALB, ECS and RDS security groups.

Application traffic flows as:

```text
Internet
   |
   v
ALB :80
   |
   v
ECS :5000
   |
   v
RDS :5432
```

RDS is private and accepts PostgreSQL traffic on port `5432` only from the ECS task security group.

## ECS and RDS

ECS Fargate runs the same application code as EC2 but selects PostgreSQL:

```text
STORAGE_BACKEND=postgres
DB_HOST=<RDS endpoint>
DB_PORT=5432
DB_NAME=migrationdb
DB_USER=<Secrets Manager>
DB_PASSWORD=<Secrets Manager>
DB_SSLMODE=require
```

RDS PostgreSQL was provisioned with:

```text
Database: migrationdb
Master user: migrationuser
Instance: db.t3.micro
Storage: 20 GiB
Credentials: RDS-managed Secrets Manager secret
```

The database credentials are injected into ECS at task startup rather than stored in the image or hardcoded in Terraform.

Automatic master-password rotation is currently disabled in staging because ECS environment-variable secrets are loaded at task startup. A production credential-rotation strategy can be introduced later.

## Database initialisation

Terraform creates the RDS database infrastructure, while the application schema is initialised separately.

The existing application image was manually launched as a **temporary one-off ECS task**. Instead of starting Gunicorn, the container command was overridden with:

```bash
python init_db.py
```

The temporary task reused the ECS private subnets, ECS security group and task definition configuration. Secrets Manager supplied the database username and password automatically.

```text
RDS provisioned
      |
      v
One-off ECS task
      |
      v
python init_db.py
      |
      v
PostgresStorage
      |
      v
schema.sql
      |
      v
products + orders tables
      |
      v
Widget A / B / C seeded
      |
      v
readiness check
```

`schema.sql` uses `CREATE TABLE IF NOT EXISTS` and `ON CONFLICT DO NOTHING`, so rerunning the initial setup does not delete existing orders or reset existing product rows.

The temporary task exits after setup. The ECS service continues to run the normal Gunicorn command.

## Health and readiness

Two separate checks are used:

```text
/health -> Flask/Gunicorn process is running
/ready  -> configured storage backend is accessible
```

The ALB uses `/health` for its health check. `/ready` is used to verify the application's selected storage backend and database access.

## CI/CD

GitHub Actions now controls the staging application and Terraform deployment flow.

```text
Push to main
      |
      v
Detect changed files
      |
      +-----------------------------+
      |                             |
 Application change           Infra-only change
      |                             |
      v                             v
 Build Docker image             Skip build
      |
      v
 Trivy scan
      |
      v
 Push immutable image to ECR
      |                             |
      +--------------+--------------+
                     |
                     v
          Staging Terraform workflow
                     |
                     v
                  Checkov
                     |
                     v
          fmt / init / validate
                     |
                     v
              Terraform plan
                     |
                     v
          Migration approval
                     |
                     v
              Terraform apply
```

Application changes pass the **exact immutable image URI** into the staging Terraform workflow. Image tags use:

```text
<commit-sha>-<workflow-run-id>-<run-attempt>
```

For infrastructure-only changes, no unnecessary image is built. The workflow retains the exact image currently used by the ECS service.

The staging pipeline includes:

- GitHub Actions AWS authentication through OIDC.
- Trivy image scanning.
- Checkov Terraform scanning.
- Terraform format and validation checks.
- Saved Terraform plans.
- GitHub `Migration` environment approval before apply.
- Workflow concurrency protection.

## Security controls implemented

- ECS tasks run in private subnets.
- RDS runs in private subnets.
- RDS access is restricted to the ECS security group.
- Database connections require SSL by default.
- Secrets Manager stores database credentials.
- Docker runs as non-root.
- ECR tags are immutable.
- ECR scanning is enabled.
- GitHub Actions uses OIDC instead of long-lived AWS credentials.
- Terraform is scanned with Checkov.
- Container images are scanned with Trivy.
- Manual approval protects Terraform apply.

## What was validated

Staging successfully passed health, PostgreSQL readiness, API read/write and persistence testing.

An order reduced Widget A from `100` to `98` and produced revenue of `59.98`. A new ECS deployment was then forced and the same order, stock and revenue remained, confirming that state now lives in RDS rather than inside the compute layer.

The complete application-change pipeline also ran successfully from change detection through image build/push and Terraform deployment.

Screenshots and short test evidence are kept in [`tests/`](tests/README.md).

---

# PROD — Cutover

## Purpose

Production is the final migration phase. It will promote the validated ECS/RDS design into the production traffic path while keeping the legacy EC2 environment available temporarily for rollback.

## Planned production architecture

```text
                    Internet
                       |
                       v
                 HTTPS :443
                       |
                       v
             Application Load Balancer
                       |
                       v
                ECS Fargate Service
                       |
                       v
                  RDS PostgreSQL
```

Production will add the controls that were intentionally not required while proving the staging migration, including HTTPS/TLS and the final traffic cutover mechanism.

## Cutover plan

The remaining production work is:

- Introduce HTTPS using ACM.
- Establish the production traffic entry point.
- Deploy/promote the validated ECS/RDS platform.
- Perform final health and readiness checks.
- Switch production traffic from legacy EC2 to ECS.
- Monitor the new platform through the rollback window.
- Keep EC2 available temporarily as the rollback target.
- Roll traffic back to EC2 if a critical issue is found.
- Decommission the legacy environment only after ECS is confirmed stable.
- Add CloudWatch dashboards, alarms and ECS Service Auto Scaling as part of the production operational layer.

The exact traffic-switch mechanism will be implemented in the next phase of the project.

---

## Migration Status

```text
DEV                              STAGING                         PROD
Legacy EC2                       ECS Fargate + RDS               Cutover
-----------                      -----------------               -------
Terraform EC2        DONE        Docker / ECR        DONE        HTTPS / ACM       NEXT
Legacy API           DONE        ALB                 DONE        Traffic switch    NEXT
Memory backend       DONE        ECS Fargate         DONE        Rollback test      NEXT
Legacy limitations   PROVEN      RDS PostgreSQL      DONE        Monitoring         NEXT
Restart data loss    PROVEN      Secrets Manager     DONE        Auto Scaling       NEXT
                                  CI/CD               DONE        Decommission EC2   LATER
                                  Persistence         PROVEN
```

The migration is currently at the end of **staging validation** and ready to move into the **production cutover phase**.
