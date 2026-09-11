# GitHub Actions Workflows

This directory contains the CI/CD and infrastructure workflows used across the EC2 → ECS migration. AWS access is performed through GitHub OIDC rather than long-lived access keys, and Terraform apply stages are separated from plan stages with environment approvals where appropriate.

## `legacy.yaml` — Legacy EC2 Provision

Provisions and updates the dev/legacy EC2 environment with Terraform. The workflow runs formatting, init, validation and plan, saves the exact plan as an artifact, waits for approval through the `Legacy` GitHub environment, and then applies that saved plan.

This workflow establishes the original EC2 baseline used to demonstrate the limitations of the memory-backed application.

## `build-and-push.yaml` — Build and Push Image to ECR

Handles application/container changes for staging. It detects whether a new image is actually required, builds the Docker image, scans it with Trivy and pushes an immutable image to Amazon ECR using a unique commit/run-based tag.

After a successful image push it calls `staging-infra.yaml` and passes the exact image URI. For infrastructure-only changes, the staging workflow can retain the image already running in ECS rather than building an unnecessary replacement.

## `staging-infra.yaml` — Staging Terraform Plan and Apply

Reusable staging infrastructure workflow. It selects either the explicitly supplied container image or the image already running in the ECS service, runs Checkov and Terraform validation/planning, saves the plan, waits for approval through the `Migration` GitHub environment and applies the exact plan.

It owns the validated ECS/RDS platform and can also be called by the production infrastructure workflow when the existing ECS service needs to be attached to the additional production target group.

## `prod-infra.yaml` — Production Terraform Plan and Apply

Provisions and maintains the production migration layer: the production ALB, weighted target groups, replacement legacy runtime and the integration required to attach the staging-owned ECS service to production.

The workflow runs Terraform and Python safety tests, preserves the current live routing when performing normal infrastructure changes, validates that the plan does not unexpectedly alter traffic, requires `Production` environment approval, applies the saved plan, calls the staging workflow to reconcile the ECS attachment, waits for ECS stability and verifies the production targets/API.

Normal production infrastructure changes therefore cannot accidentally perform the migration cutover.

## `prod-cutover.yaml` — Production Cutover or Rollback

A manual-only workflow used to change production traffic between `legacy` and `ecs`. The selected destination is converted into Terraform listener weights:

```text
Cutover:  legacy = 0,   ecs = 100
Rollback: legacy = 100, ecs = 0
```

Before applying a routing change, the workflow checks destination health, creates a Terraform plan and uses the routing guard script to restrict the plan to the permitted cutover change. It then waits for `Production` approval, rechecks destination health and the saved plan, applies it, and verifies routing/API readiness afterwards.

Rollback changes routing only; data written to RDS is not copied back into the legacy application's in-memory storage.

## Workflow Evidence

Screenshots of successful workflow runs are stored separately in [`../../ECS-migration/workflow-results/`](../../ECS-migration/workflow-results/) so this README explains the workflows without duplicating execution evidence.