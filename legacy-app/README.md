# EC2 Legacy Application

This is a **legacy Flask application** running on a single EC2 instance behind Nginx. It represents the current state of an application scheduled for migration to a modern containerized platform.

## Architecture

```
Internet → EC2 Instance (Public Subnet)
              ├── Nginx (Port 80)
              └── Flask App (Gunicorn, Port 5000)
```

### Components

- **Flask Application**: Python/Flask API with REST endpoints
- **Gunicorn**: WSGI HTTP Server running the Flask app
- **Nginx**: Reverse proxy serving HTTP on port 80
- **Systemd**: Service manager for the Flask application
- **Terraform**: Infrastructure as Code for provisioning

## Application Features

The Flask API provides the following endpoints:

- `GET /health` - Health check endpoint
- `GET /api/v1/products` - List all products
- `GET /api/v1/products/{id}` - Get specific product
- `POST /api/v1/orders` - Create a new order
- `GET /api/v1/orders` - List all orders
- `GET /api/v1/stats` - Application statistics

## Prerequisites

- **AWS Account** with appropriate permissions
- **Terraform** >= 1.5.0
- **AWS CLI** configured (for manual testing)
- **SSH Key Pair** created in AWS (optional, for SSH access)

## Deployment

### 1. Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review Plan

```bash
terraform plan
```

### 4. Deploy Infrastructure

```bash
terraform apply
```

This will create:
- VPC with public and private subnets
- Internet Gateway and Route Tables
- Security Groups
- EC2 instance with Elastic IP
- S3 bucket for application files
- IAM roles and policies
- (Optional) Route53 DNS record

### 5. Wait for Application Setup

The EC2 instance will automatically:
1. Download application files from S3
2. Install system dependencies
3. Set up Python virtual environment
4. Configure Nginx
5. Start the Flask application via systemd

Check the instance status:

```bash
# Get instance IP
terraform output ec2_instance_public_ip

# SSH into instance (if key pair configured)
ssh -i ~/.ssh/your-key.pem ubuntu@<instance-ip>

# Check application logs
sudo journalctl -u flask-app -f
sudo tail -f /var/log/nginx/flask-access.log
```

### 6. Test the Application

```bash
# Get application URL
APP_URL=$(terraform output -raw application_url)
echo $APP_URL

# Health check
curl $APP_URL/health

# List products
curl $APP_URL/api/v1/products

# Create an order
curl -X POST $APP_URL/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}'
```

## Application Access

The application will be accessible via:
- **Public IP**: Use `terraform output ec2_instance_public_ip`
- **Domain Name**: If Route53 is configured, use `terraform output route53_record`

Default endpoint: `http://<ip-or-domain>/health`

## Logs

Application logs are located on the EC2 instance:

- **Application logs**: `/var/log/flask-app/`
  - `access.log` - Gunicorn access logs
  - `error.log` - Gunicorn error logs
- **Systemd logs**: `sudo journalctl -u flask-app -f`
- **Nginx logs**: `/var/log/nginx/`
  - `flask-access.log` - Nginx access logs
  - `flask-error.log` - Nginx error logs

## Service Management

```bash
# Check service status
sudo systemctl status flask-app
sudo systemctl status nginx

# Restart application
sudo systemctl restart flask-app

# View logs
sudo journalctl -u flask-app -f
```

## Troubleshooting

### Application not responding

1. Check if services are running:
   ```bash
   sudo systemctl status flask-app
   sudo systemctl status nginx
   ```

2. Check application logs:
   ```bash
   sudo journalctl -u flask-app -n 50
   tail -f /var/log/flask-app/error.log
   ```

3. Test Flask app directly:
   ```bash
   curl http://localhost:5000/health
   ```

4. Check Nginx configuration:
   ```bash
   sudo nginx -t
   sudo tail -f /var/log/nginx/flask-error.log
   ```

### Health check fails

1. Ensure Gunicorn is bound to `127.0.0.1:5000`:
   ```bash
   sudo netstat -tlnp | grep 5000
   ```

2. Test health endpoint directly:
   ```bash
   curl http://127.0.0.1:5000/health
   ```

### Permission issues

Ensure correct ownership:

```bash
sudo chown -R ubuntu:ubuntu /opt/flask-app
sudo chown -R ubuntu:ubuntu /var/log/flask-app
```

## Current Limitations

This legacy setup has several limitations that make it unsuitable for production at scale:

- ❌ **No autoscaling**: Single instance, no horizontal scaling
- ❌ **No high availability**: Single point of failure
- ❌ **Manual deployments**: No CI/CD pipeline
- ❌ **Inconsistent logging**: Logs scattered across instance
- ❌ **No observability**: Limited metrics and monitoring
- ❌ **Manual configuration**: No infrastructure as code for app config
- ❌ **No containerization**: Difficult to replicate environments
- ❌ **Single AZ**: Not resilient to AZ failures
- ❌ **No blue/green deployments**: Downtime during updates
- ❌ **Security**: App runs in public subnet with public IP

## Migration Target

The target platform will move this workload to:

- ✅ **Amazon ECS (Fargate)**: Containerized, managed service
- ✅ **Application Load Balancer**: High availability, health checks
- ✅ **Private subnets**: Enhanced security
- ✅ **Auto-scaling**: Horizontal scaling based on demand
- ✅ **CI/CD pipeline**: GitHub Actions with OIDC
- ✅ **CloudWatch**: Centralized logging and metrics
- ✅ **Multi-AZ**: High availability
- ✅ **Zero-downtime deployments**: Blue/green or rolling updates

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

⚠️ **Warning**: This will delete all resources including the EC2 instance and data.

## Migration Considerations

The migration plan should address:

1. **DNS Cutover Strategy**: Use Route53 weighted routing or ALIAS record swap
2. **Health Checks**: Ensure ECS health checks pass before routing traffic
3. **Data Migration**: Account for stateful data currently held in memory
4. **Monitoring**: Establish CloudWatch alarms before cutover
5. **Rollback Plan**: Keep the EC2 instance available during the initial cutover window
6. **Testing**: Validate all endpoints on ECS before full traffic migration

### Storage backends

Both deployments use `app/app.py` and the same API routes. Set
`STORAGE_BACKEND=memory` for the legacy EC2 deployment (configured in the
systemd unit), or `STORAGE_BACKEND=postgres` for ECS (configured in its Terraform
module). Local development defaults to memory. Unknown backends fail at startup;
database failures never switch to memory.

Memory storage starts with the original three sample products. Orders and stock
are local to each Gunicorn worker and reset on restart, preserving the legacy
application's limitations. Data is not transferred to RDS automatically.

PostgreSQL requires `DB_HOST`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD`; `DB_PORT`
defaults to `5432`. Connections use a five-second timeout and `DB_SSLMODE=require`
by default. Provision the `products` and `orders` tables before testing the API.
ECS still injects credentials at task startup: after secret rotation, redeploy
its tasks to obtain the current password. `/health` checks the process only.

Deploy the updated EC2 application package and systemd unit together. For ECS,
the image workflow builds and pushes the image, then calls staging Terraform
to deploy that exact image and the backend setting together. Neither deployment requires EC2 to connect to RDS.

Run the storage and API checks after installing `app/requirements.txt`:

```bash
python -m unittest discover -s legacy-app/tests -v
```

The PostgreSQL transaction tests use mocked connections; they do not validate a
live database or its schema.

### Initialize RDS and check readiness

The container includes `schema.sql` and `init_db.py`. After building the new image
and deploying its task definition, run a **standalone Fargate task** using that
same task definition, private subnets, and ECS security group. In the application
container's command override, use:

```json
["python", "init_db.py"]
```

This reuses the task's database environment and Secrets Manager credentials.
Wait for the task to stop with exit code **0**, and check its CloudWatch logs for
`Database schema and sample products are ready.` A failed task must be resolved
before treating the database as initialized. This command is explicit; the normal
web server startup and Terraform pipeline do not run it automatically.

The initializer creates `products` and `orders` in one transaction and inserts
Widget A, B, and C. Re-running does not reset stock, overwrite existing products,
or remove orders. Concurrent initializers are serialized. This is initial schema
setup, not an upgrade mechanism for an incompatible existing schema.

Then request `/ready` through the application's existing URL:

```bash
curl -i https://YOUR_API_HOST/ready
```

Use `http://` if your ALB is configured for HTTP. ECS success returns HTTP 200:

```json
{"status":"ready","storage":"postgres"}
```

A connection, authentication, query timeout, missing table, or missing required
column returns HTTP 503 with `status: not_ready`; details go to server logs rather
than the response. The check reads table metadata through zero-row SELECTs; it
makes no data changes and does not prove write permissions. EC2 reports
`storage: memory`, which does not claim database connectivity. `/health` remains
a process health check; the existing load balancer health-check path is unchanged.

### Ordered image and infrastructure deployments

`build-and-push.yaml` coordinates relevant pushes to main. Its `changes` job
compares all files changed by the push:

- App/Docker changes: build, scan, push, then call staging with that exact image URI.
- Staging infrastructure changes only: skip the build and call staging with no
  image override, retaining the image in the ECS service's task definition.
- Both: build first, then deploy the new image and infrastructure together.

`staging-infra.yaml` is reusable and no longer starts independently on push,
preventing duplicate deployments. Its existing plan/apply jobs, scans, and
`Migration` environment approval remain. Terraform no longer searches ECR for
"latest". The AWS workflow role needs `ecs:DescribeServices` and
`ecs:DescribeTaskDefinition` for infrastructure-only runs.

Manual build runs build and deploy a new image. Manual staging runs accept an
optional `container_image`: blank retains the current service image; an explicit
URI deploys that image. If no service exists, run the build workflow or supply an
image URI. A failed build/push blocks deployment. Existing concurrency controls
serialize active runs; GitHub may replace older pending runs with newer ones.

The schema initializer remains a separate explicit task; these workflow changes
do not automatically initialize the database.
