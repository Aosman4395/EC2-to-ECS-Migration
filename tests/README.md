# Migration Test Evidence

This directory documents the functional tests used to compare the legacy EC2 application with the migrated ECS Fargate + RDS platform.

The screenshots referenced below should be stored in `tests/screenshots/` using the listed filenames.

## 1. ECS Health and RDS Readiness

**Screenshot:** `screenshots/01-ecs-health-readiness-test.png`

The ECS application was tested through the staging Application Load Balancer.

Validated endpoints included:

```bash
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/health
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/ready
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/products
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/products/1
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/orders
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/stats
```

Results confirmed:

- Flask/Gunicorn was healthy behind the ALB.
- `/ready` returned `storage: postgres`.
- ECS could connect to RDS successfully.
- All three seeded products were returned.
- The orders and statistics tables were accessible.

Expected readiness result:

```json
{"status":"ready","storage":"postgres"}
```

## 2. ECS RDS Write Test

**Screenshot:** `screenshots/02-ecs-rds-api-test.png`

An order for two units of Widget A was created through the ECS API:

```bash
curl -X POST \
  http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{"product_id":1,"quantity":2}'
```

The API was then queried again:

```bash
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/orders
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/products/1
curl http://migration-staging-alb-694536568.eu-west-2.elb.amazonaws.com/api/v1/stats
```

Observed result:

```text
Order count:   1
Widget A stock: 100 -> 98
Total revenue: 59.98
```

This proves that the API can write to PostgreSQL and that the order, stock update and statistics are stored consistently.

## 3. ECS Persistence After Task Replacement

**Screenshot:** `screenshots/03-ecs-rds-persistence-test.png`

A new ECS deployment was forced:

```bash
aws ecs update-service \
  --cluster migration-ecs-cluster \
  --service api-service \
  --force-new-deployment \
  --region eu-west-2
```

After the replacement task became healthy, the API was queried again.

The following values remained:

```text
Order count:   1
Widget A stock: 98
Total revenue: 59.98
```

This proves that state is stored in RDS rather than inside the ECS container and survives task replacement.

## 4. Legacy EC2 Memory Test

**Screenshot:** `screenshots/04-ec2-memory-api-test.png`

The legacy EC2 API was validated with:

```bash
curl http://3.9.50.41/health
curl http://3.9.50.41/ready
curl http://3.9.50.41/api/v1/products
curl http://3.9.50.41/api/v1/products/1
curl http://3.9.50.41/api/v1/orders
curl http://3.9.50.41/api/v1/stats
```

Readiness confirmed that the legacy deployment was using:

```json
{"status":"ready","storage":"memory"}
```

An order for two Widget A units was then submitted. Stock changed from `100` to `98`, demonstrating that the legacy application could modify state while the process remained alive.

The test also exposed the original multi-worker in-memory limitation: because Gunicorn workers do not share Python memory, order/stat responses can be inconsistent between requests even before a restart.

## 5. Legacy EC2 Data Loss After Restart

**Screenshot:** `screenshots/05-ec2-memory-data-loss-after-restart.png`

The EC2 instance was manually rebooted after changing the in-memory application state.

Once the application became healthy again, the API was queried:

```bash
curl http://3.9.50.41/ready
curl http://3.9.50.41/api/v1/orders
curl http://3.9.50.41/api/v1/products/1
curl http://3.9.50.41/api/v1/stats
```

After restart:

```text
Orders:        0
Widget A stock: 100
Total revenue: 0
```

This demonstrates the central legacy storage problem: application state exists only in process memory and is lost when the compute is restarted.

## 6. CI/CD Pipeline Validation

**Screenshot:** `screenshots/06-successful-staging-pipeline.png`

The GitHub Actions staging pipeline completed successfully through the full application-change path:

```text
changes
   -> build-and-push
   -> terraform-plan
   -> terraform-apply
```

The workflow detected the application change, built the Docker image, scanned it with Trivy, pushed the immutable image to ECR, passed the exact image URI to the reusable staging workflow, generated a Terraform plan and deployed it after the configured environment approval.

This validates the automated delivery path from source change to ECS deployment.

## Result Summary

| Test | Legacy EC2 | ECS + RDS |
| --- | --- | --- |
| Health | Pass | Pass |
| Storage readiness | Memory | PostgreSQL |
| Read products | Pass | Pass |
| Create order | Pass | Pass |
| Stock update | In-memory | Persisted in RDS |
| Compute restart/replacement | State lost | State retained |
| Automated deployment | No | Yes |

The tests demonstrate the main migration improvement: **application state has been separated from compute and moved to persistent PostgreSQL storage, allowing ECS tasks to be replaced without losing business data.**
