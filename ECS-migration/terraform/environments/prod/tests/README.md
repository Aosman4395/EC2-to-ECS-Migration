# Production Test Screenshots

## Pre-cutover

![Pre-cutover API endpoints](screenshots/01-pre-cutover-api.png.png)

Tests the production API before cutover, with `/ready` confirming the legacy in-memory backend.

![Pre-cutover traffic routing](screenshots/02-pre-cutover-routing.png.png)

Confirms the production listener routes 100% of traffic to legacy EC2 and 0% to ECS before cutover.

![Pre-cutover target health](screenshots/03-pre-cutover-target-health.png.png)

Confirms both the legacy EC2 and ECS target groups have healthy targets before switching traffic.

## Post-cutover

![Post-cutover traffic routing](screenshots/04-post-cutover-routing.png.png)

Confirms the production listener routes 100% of traffic to ECS and 0% to legacy EC2 after cutover.

![Post-cutover API endpoints](screenshots/05-post-cutover-api.png.png)

Confirms `/health`, `/ready`, `/api/v1/products`, `/api/v1/orders` and `/api/v1/stats` return HTTP 200 after cutover.
