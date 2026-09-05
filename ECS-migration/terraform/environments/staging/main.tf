# Staging migration environment
#
# The legacy EC2 environment remains running in dev and is read here through
# remote state for side-by-side validation. This state owns only the new ECS
# staging infrastructure.

# Reference the existing legacy EC2 environment without recreating it.
data "terraform_remote_state" "legacy_dev" {
  backend = "s3"

  config = {
    bucket = "aosman-ecs-migration-tf-state"
    key    = "environments/dev/terraform.tfstate"
    region = var.aws_region
  }
}

# New target network for the ECS staging platform.
module "vpc" {
  source = "../../infrastructure/modules/vpc"

  vpc_name = "ecs-migration-staging-vpc"
}

# IAM roles used by the ECS task definition.
module "iam" {
  source = "../../infrastructure/modules/iam"
}

# Internet-facing ALB in the public subnets.
module "alb" {
  source = "../../infrastructure/modules/alb"

  alb_name          = "migration-staging-alb"
  alb_sg_name       = "migration-staging-alb-sg"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = var.certificate_arn
}

# New ECS Fargate application service in private subnets.
module "ecs" {
  source = "../../infrastructure/modules/ecs"

  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.ecs_private_subnet_ids
  alb_security_group_id = module.alb.alb_sg_id
  target_group_arn      = module.alb.target_group_arn

  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.task_role_arn

  container_name  = var.container_name
  container_port  = var.container_port
  container_image = var.container_image
  log_group_name  = "/ecs/migration-staging-api"
  aws_region      = var.aws_region
}

# RDS, Secrets Manager integration, service autoscaling, CloudWatch dashboards,
# alarms and migration traffic shifting are intentionally added later.
