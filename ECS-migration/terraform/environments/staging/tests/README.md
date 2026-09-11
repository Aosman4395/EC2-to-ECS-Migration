# Staging Test Screenshots

![ECS health and readiness](screenshots/01-ecs-health-readiness-test.png.png)

Tests ECS application health and readiness to use the PostgreSQL database.

![ECS RDS API test](screenshots/02-ecs-rds-api-test.png.png)

Tests order creation, order retrieval, stock updates and statistics using the ECS API backed by RDS.

![ECS RDS persistence test](screenshots/03-ecs-rds-persistence-test.png.png)

Tests whether orders, stock and revenue stored in RDS persist across an ECS redeployment.

![EC2 memory API](screenshots/04-ec2-memory-api-test.png.png)

Tests order creation, order retrieval, stock updates and statistics using the legacy EC2 API with in-memory storage.

![EC2 memory data loss after restart](screenshots/05-ec2-memory-data-loss-after-restart.png)

Tests whether restarting the legacy EC2 application loses in-memory orders and resets product stock.

