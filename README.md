# EC2 to ECS Fargate Migration

## Overview

This project demonstrates the migration of a legacy application running on a single Amazon EC2 instance to a modern, containerised architecture using Amazon ECS with AWS Fargate.

The existing application is a Python Flask API deployed to EC2 and served through Nginx. The legacy deployment represents a traditional workload with several limitations, including manual deployment processes, no application-level autoscaling, a single compute instance, and limited observability.

Rather than simply rebuilding the application on ECS, this project focuses on the full migration lifecycle:

**Understand the existing environment → establish a working baseline → containerise the application → build the ECS platform → introduce CI/CD and observability → validate the new environment → safely cut traffic from EC2 to ECS.**

The aim is to approach the migration as a real production workload where availability, security, rollback capability, observability and controlled cutover are important considerations.

## Project Goals

The final platform will migrate the Flask application from EC2 to **Amazon ECS using AWS Fargate**, removing the need to directly manage application servers.

The project aims to implement:

- Docker containerisation of the legacy Flask application
- Amazon ECR for container image storage
- Amazon ECS using the Fargate launch type
- Application Load Balancer for application traffic
- ECS services and task definitions
- Multi-AZ networking
- Public and private subnet separation
- Security groups following least-privilege principles
- Infrastructure as Code using Terraform
- Automated CI/CD using GitHub Actions
- Centralised application logging using Amazon CloudWatch
- ECS service health checks
- Horizontal application scaling
- Deployment rollback capability
- A controlled EC2 → ECS production cutover strategy

## Legacy Architecture

The starting environment consists of a Python Flask API running on a single EC2 instance.

The existing deployment process uses Terraform to provision the AWS infrastructure.

During EC2 startup, a user data script retrieves the application package from Amazon S3 and configures the instance so that the Flask application can be accessed through the EC2-hosted environment.

The legacy architecture can broadly be represented as:

```text
Client
  |
  v
EC2
  |
Nginx
  |
Flask API
```

This architecture provides a useful migration baseline but introduces several production concerns.

### Legacy Limitations

The current platform has:

- A single EC2 application host
- No application-level autoscaling
- Manual/server-based application deployment
- Tight coupling between infrastructure and application deployment
- Limited deployment rollback capabilities
- Inconsistent application logging
- Server management overhead
- A potential single point of failure

These limitations provide the main drivers for the migration.

## Target Architecture

The target platform will replace the EC2-hosted workload with containerised ECS tasks running on AWS Fargate.

```text
                        Internet
                            |
                            v
                 Application Load Balancer
                            |
                            v
                     ECS Service
                       /       \
                      v         v
                Fargate Task  Fargate Task
                      |
                      v
                 Flask Container
```

Container images will be stored within Amazon ECR and deployments will eventually be automated through GitHub Actions.

Terraform will continue to manage the AWS infrastructure.

The target environment will also introduce CloudWatch logging, health checks, autoscaling and safer deployment mechanisms.

## Current Progress

### Phase 1 — Repository Setup

The migration repository has been created and prepared for development.

Completed work:

- Created the migration repository
- Added the legacy application under `legacy-app/`
- Verified that the legacy application files are correctly tracked by Git
- Removed unnecessary training and assignment references
- Established the repository as the working location for the migration
- Pushed the repository to GitHub

This gives the project a clean starting point while preserving the original application that will be migrated.

### Phase 2 — Establish the Legacy Baseline

Before changing the architecture, the existing EC2 deployment is being reproduced and validated.

This is an important part of the migration because the current application behaviour needs to be understood before introducing containers or ECS.

The existing Terraform configuration has been reviewed to understand how the legacy environment works.

At a high level:

1. Terraform provisions the required AWS infrastructure.
2. An EC2 instance is created.
3. EC2 user data runs during instance startup.
4. The application is retrieved from Amazon S3.
5. The application is configured on the instance.
6. Nginx exposes the application.
7. The application becomes accessible through the EC2 environment.

Understanding this deployment flow provides the baseline against which the ECS environment can later be tested.

### Baseline Validation

Once the EC2 environment is deployed, the application endpoints will be tested to confirm that the legacy application behaves correctly.

The results will provide a known-good baseline before the migration begins.

This prevents application problems from being incorrectly attributed to ECS later in the project.
