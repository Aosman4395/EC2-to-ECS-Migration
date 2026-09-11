# EC2 to ECS Fargate Migration

## Project Overview

This project demonstrates an end-to-end migration of a legacy Python/Flask ordering API from a single Amazon EC2 instance with in-memory state to a containerised Amazon ECS Fargate platform backed by Amazon RDS PostgreSQL.

Rather than replacing the legacy workload in one step, the migration was delivered through **dev, staging and production phases**. The original application was first reproduced and its limitations proven, the ECS/RDS platform was then built and validated alongside it, and finally a controlled production cutover moved 100% of traffic from EC2 to ECS.

```text
DEV / LEGACY EC2  ->  STAGING / ECS + RDS  ->  PROD / CONTROLLED CUTOVER
```

The project uses **Terraform, AWS, Docker, GitHub Actions, OIDC, ECR, ECS Fargate, RDS PostgreSQL, Secrets Manager, CloudWatch, ALB, Trivy and Checkov**.

## Contents

- [Application](#application)
- [Migration Journey](#migration-journey)
- [DEV — Legacy EC2](#dev--legacy-ec2)
- [STAGING — ECS Fargate + RDS](#staging--ecs-fargate--rds)
- [PROD — Controlled Cutover](#prod--controlled-cutover)
- [CI/CD and Security](#cicd-and-security)
- [Testing and Evidence](#testing-and-evidence)
- [Project Management](#project-management)
- [Final Result](#final-result)

---

## Application

The Flask API contains three sample products and supports product reads, order creation, stock updates and order statistics.

```text
GET  /health
GET  /ready
GET  /api/v1/products
GET  /api/v1/products/{id}
POST /api/v1/orders
GET  /api/v1/orders
GET  /api/v1/stats
```

The same application code supports both sides of the migration. `STORAGE_BACKEND` selects the storage implementation:

```text
                    Flask API
                       |
                STORAGE_BACKEND
                  /          \
               memory      postgres
                 |             |
             Legacy EC2       RDS
```

There is deliberately no automatic PostgreSQL-to-memory fallback. If the database is unavailable, readiness fails rather than silently falling back to non-persistent storage.

---

## Migration Journey

### Before

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

The legacy design had several limitations: a single point of failure, no application autoscaling, server-coupled deployments, non-durable order/stock state, inconsistent state between Gunicorn workers, and host-dependent operations.

### After

```text
Internet
   |
   v
Production ALB
   |
   v
ECS Fargate Service
   |
   v
Flask API
   |
   v
RDS PostgreSQL

ECR             -> immutable container images
Secrets Manager -> database credentials
CloudWatch      -> logs, metrics and alarms
GitHub Actions  -> CI/CD and controlled deployment
Terraform       -> infrastructure as code
```

The compute layer is now replaceable while application state remains durable in PostgreSQL.

---

# DEV — Legacy EC2

## Purpose

Dev reproduced the original workload and established a measurable **before state** for the migration.

Terraform provisioned the VPC, public subnet, Internet Gateway, routing, security group and EC2 instance. Nginx exposed the application on port 80 and proxied requests to Gunicorn on port 5000. The Flask application ran with:

```text
STORAGE_BACKEND=memory
```

The legacy API was validated with real requests. Testing demonstrated that in-memory state was not reliable: order/stock results could become inconsistent between requests and state was lost when the application/runtime restarted.

Detailed dev validation and screenshots are intentionally kept out of this main README and are documented in [`ECS-migration/terraform/environments/dev/tests/`](ECS-migration/terraform/environments/dev/tests/README.md).

---

# STAGING — ECS Fargate + RDS

## Purpose

Staging built the migration destination alongside the legacy environment so the new platform could be tested before any production traffic was moved.

## Architecture

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

              Secrets Manager -> ECS Task
              CloudWatch      -> Logs / Metrics / Alarms
```

The VPC separates the platform across **public ALB subnets, private ECS subnets and private RDS subnets**. ECS uses NAT egress, while RDS remains private and accepts PostgreSQL traffic only from the ECS security group.

## Container and Registry

The application was containerised with `python:3.9-slim` and Gunicorn. The image runs as a dedicated **non-root user** and is stored in Amazon ECR with **immutable image tags** and image scanning enabled.

Application changes are built into unique images using the commit SHA, workflow run ID and run attempt, giving each deployment a traceable image rather than reusing a mutable tag.

## ECS and PostgreSQL

ECS Fargate runs the application with:

```text
STORAGE_BACKEND=postgres
DB_HOST=<RDS endpoint>
DB_PORT=5432
DB_NAME=migrationdb
DB_USER=<Secrets Manager>
DB_PASSWORD=<Secrets Manager>
DB_SSLMODE=require
```

Database credentials are supplied through Secrets Manager rather than stored in the image or hardcoded in Terraform.

The schema was initialised using a temporary one-off ECS task running `python init_db.py`. The schema is idempotent, allowing initialisation to be rerun without deleting existing orders or resetting seeded products.

## Resilience and Operations

The staging platform includes ECS Service Auto Scaling and CloudWatch monitoring/alarms. `/health` verifies the application process, while `/ready` verifies that the configured storage backend is actually accessible.

Staging validation proved that the API could create and retrieve orders through ECS/RDS and that the data survived ECS task replacement. This demonstrated the key migration outcome: **state moved out of the compute layer and into durable PostgreSQL storage**.

The full staging test evidence is documented in [`ECS-migration/terraform/environments/staging/tests/`](ECS-migration/terraform/environments/staging/tests/README.md).

---

# PROD — Controlled Cutover

## Purpose

Production introduced a dedicated migration entry point and a controlled traffic-switch mechanism. The validated ECS/RDS platform remained owned by staging Terraform rather than being duplicated into a second ECS/RDS stack.

Because the original dev VPC and staging VPC both use `10.0.0.0/16`, the original EC2 instance could not simply be routed behind the production ALB. A replacement legacy runtime was therefore created inside the staging VPC using the same frozen memory-backed application behaviour.

## Migration Architecture

```text
                         Production ALB
                              |
                       weighted listener
                        /             \
                       /               \
              Legacy target         ECS target
                  group                group
                    |                    |
          Replacement legacy EC2    Existing ECS service
          STORAGE_BACKEND=memory    STORAGE_BACKEND=postgres
                                         |
                                         v
                                   RDS PostgreSQL
```

The existing staging ALB remained attached to the ECS service. Production added a second ECS target group rather than creating another ECS service.

A non-secret SSM Parameter Store integration contract passes the production ECS target-group ARN and production ALB security-group ID to the staging-owned Terraform configuration. This preserves clear resource ownership between Terraform states.

## Cutover

Production infrastructure was first deployed with:

```text
Legacy = 100%
ECS    =   0%
```

Before cutover, both target groups were checked for health and the legacy production API was verified. The dedicated manual cutover workflow then performed a guarded Terraform change to:

```text
Legacy =   0%
ECS    = 100%
```

The workflow validates the requested destination before the change, restricts the Terraform plan to the permitted routing change, requires approval through the GitHub `Production` environment, rechecks destination health after approval, applies the exact saved plan and verifies the API afterwards.

The cutover completed successfully. Post-cutover validation confirmed **100% ECS routing** and HTTP 200 responses from the production `/health`, `/ready`, products, orders and stats endpoints.

Production evidence, including pre-cutover routing, target health, post-cutover routing and API validation, is documented in [`ECS-migration/terraform/environments/prod/tests/`](ECS-migration/terraform/environments/prod/tests/README.md).

The final operational step is retirement of the temporary legacy migration runtime once the ECS/RDS path has been retained as the production destination.

---

## CI/CD and Security

GitHub Actions provides separate workflows for the legacy environment, image build/deployment, staging infrastructure, production infrastructure and the manual production cutover. AWS authentication uses **GitHub OIDC** instead of stored long-lived AWS access keys.

The delivery path includes **Trivy container scanning, Checkov Terraform scanning, Terraform formatting/validation, saved Terraform plans, environment approvals and concurrency controls**. Production additionally uses routing guardrails and application/target-health verification before and after traffic changes.

The workflow YAML files are documented briefly in [`.github/workflows/README.md`](.github/workflows/README.md), while screenshots of successful workflow runs are kept separately in [`ECS-migration/workflow-results/`](ECS-migration/workflow-results/).

Key security controls implemented include private ECS/RDS subnets, security-group segmentation, SSL-required database connections, Secrets Manager credentials, non-root containers, immutable ECR images, OIDC-based CI/CD authentication, Trivy/Checkov scanning and manual deployment approvals.

---

## Testing and Evidence

Evidence is deliberately organised beside the environment it validates instead of duplicating screenshots throughout this README:

| Phase | Evidence |
| --- | --- |
| Dev | [`dev/tests`](ECS-migration/terraform/environments/dev/tests/README.md) — legacy API behaviour and state inconsistency |
| Staging | [`staging/tests`](ECS-migration/terraform/environments/staging/tests/README.md) — health/readiness, ECS→RDS API behaviour and persistence |
| Production | [`prod/tests`](ECS-migration/terraform/environments/prod/tests/README.md) — pre-cutover API/routing/target health and successful post-cutover validation |
| Workflow runs | [`workflow-results`](ECS-migration/workflow-results/) — successful Dev, staging, production and cutover workflow evidence |
| Automation tests | [`tests`](tests/README.md) — production routing and verification script tests |
| Operational scripts | [`scripts`](scripts/README.md) — API, container and production verification helpers |

---

## Project Management

The migration was managed through a **GitHub Projects Kanban backlog** rather than being implemented as one large change. Work was broken into issues covering the legacy baseline, containerisation, ECR, PostgreSQL integration, ECS/RDS infrastructure, CI/CD, production migration infrastructure, controlled cutover and legacy retirement.

This made the migration incremental: each phase had a clear acceptance point before the next phase was started, while the board tracked work through Ready, In Progress, In Review and Done.

> **Project board screenshot:** upload the supplied board image to `ECS-migration/project-management/tickets-board.png`, then the image below will render in the repository.

![GitHub Projects migration backlog](ECS-migration/project-management/tickets-board.png)

---

## Final Result

```text
Legacy EC2 baseline                 COMPLETE
Containerisation                    COMPLETE
ECR / immutable images              COMPLETE
ECS Fargate platform                COMPLETE
RDS PostgreSQL persistence          COMPLETE
Secrets Manager integration         COMPLETE
Private networking                  COMPLETE
CloudWatch monitoring               COMPLETE
ECS Service Auto Scaling            COMPLETE
GitHub Actions CI/CD                COMPLETE
OIDC authentication                 COMPLETE
Security scanning                   COMPLETE
Production migration ALB            COMPLETE
Pre-cutover validation              COMPLETE
Controlled EC2 -> ECS cutover       COMPLETE
Post-cutover production validation  COMPLETE
Legacy retirement                   FINAL CLEANUP
```

The application has successfully moved from a **single, stateful EC2 runtime** to a **containerised ECS Fargate service with durable RDS PostgreSQL storage**, with the migration executed through an observable, approval-gated and testable production cutover process.