# EC2 to ECS Fargate Migration

## Overview

This project migrates a legacy Python/Flask ordering API from a single Amazon EC2 instance to a containerised Amazon ECS Fargate platform.

The migration is being completed incrementally: first understanding and testing the legacy workload, then containerising it, externalising application state, building the AWS infrastructure, and finally introducing CI/CD, observability and a safe cutover strategy.

**EC2 baseline → Docker → RDS persistence → ECS Fargate → CI/CD & observability → cutover**

## Contents

- [Target Architecture](#target-architecture)
- [Legacy Application](#legacy-application)
- [Legacy Architecture](#legacy-architecture)
- [Baseline Testing](#baseline-testing)
- [Key Finding — In-Memory State](#key-finding--in-memory-state)
- [Docker Containerisation](#docker-containerisation)
- [Application Changes for Data Persistence](#application-changes-for-data-persistence)

## Target Architecture

```text
                     Internet
                        |
                        v
             Application Load Balancer
                        |
                        v
                  ECS Fargate Service
                   /             \
                  v               v
              ECS Task         ECS Task
                   \             /
                    v           v
                 RDS PostgreSQL
                        |
                 Secrets Manager
```

The target platform will use:

- Amazon ECR for container images
- Amazon ECS Fargate for application compute
- Application Load Balancer for traffic distribution
- Private ECS subnets across multiple Availability Zones
- Amazon RDS PostgreSQL for persistent shared state
- AWS Secrets Manager for database credentials
- Terraform for infrastructure provisioning
- GitHub Actions with AWS OIDC for CI/CD
- Amazon CloudWatch for logs, metrics and alarms
- ECS Service Auto Scaling
- A controlled EC2 → ECS cutover and rollback strategy

## Legacy Application

The inherited workload is a Flask API served by Gunicorn behind Nginx. It supports:

- `GET /health`
- `GET /api/v1/products`
- `GET /api/v1/products/{id}`
- `POST /api/v1/orders`
- `GET /api/v1/orders`
- `GET /api/v1/stats`

The original application stored products, stock and orders directly in Python memory.

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
```

The legacy environment had several limitations: a single point of failure, no autoscaling, manual/server-based deployments, limited monitoring and rollback capability, and non-persistent application state.

## Baseline Testing

Before making migration changes, the EC2 deployment was reproduced with Terraform and the existing API was tested.

| Test | Result |
| --- | --- |
| `GET /health` | Successful |
| `GET /api/v1/products` | Three products returned |
| `GET /api/v1/products/1` | Product returned |
| `POST /api/v1/orders` | Order created |
| `GET /api/v1/orders` | Order returned |
| `GET /api/v1/stats` | Statistics returned |

![Legacy API validation](screenshots/legacy-api-validation.png.png)

## Key Finding — In-Memory State

Testing exposed a data consistency problem. After an order reduced Widget A stock from `100` to `98`, repeated requests sometimes returned `100` and sometimes `98`.

![Legacy state inconsistency](screenshots/legacy-state-inconsistency.png.png)

Gunicorn uses multiple worker processes, and each worker had its own copy of the Python in-memory data. Restarting the application would also remove orders and stock changes entirely.

```text
Gunicorn
 /  |  \
W1  W2  W3
98  100 100
```

Moving this unchanged into multiple ECS tasks would make the problem worse, so application state must be externalised.

## Docker Containerisation

The Flask application was containerised and tested locally before introducing ECS.

The Docker image:

- Uses `python:3.9-slim`
- Installs dependencies from `requirements.txt`
- Runs the application with Gunicorn on port `5000`
- Runs as a dedicated non-root `legacyuser`
- Uses `.dockerignore` to exclude unnecessary and sensitive local files

The container was successfully built and started locally. The runtime user was verified with `docker exec`, and the `/health` endpoint returned HTTP `200`.

## Application Changes for Data Persistence

Before building the new Terraform infrastructure, the application was reviewed and the original in-memory storage was identified as unsuitable for ECS.

`app.py` was updated to:

- Store products and orders in PostgreSQL instead of Python memory
- Connect using database environment variables rather than hardcoded credentials
- Persist orders and stock changes across task restarts
- Allow multiple ECS tasks to use the same shared database
- Add the PostgreSQL dependency to `requirements.txt`

The updated Docker image was rebuilt successfully and `/health` returned HTTP `200`. Database-backed endpoints will be fully tested once Amazon RDS PostgreSQL is provisioned and connected.
