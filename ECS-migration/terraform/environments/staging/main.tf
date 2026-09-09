# Reference the existing legacy EC2 environment without recreating it.
data "terraform_remote_state" "legacy_dev" {
  backend = "s3"

  config = {
    bucket = "aosman-ecs-bootstrap-bucket"
    key    = "environments/dev/terraform.tfstate"
    region = var.aws_region
  }
}

#New ECS staging environment
module "vpc" {
  source = "../../modules/vpc"

  vpc_name = "ecs-migration-staging-vpc"
}

module "iam" {
  source = "../../modules/iam"
}

module "alb" {
  source = "../../modules/alb"

  alb_name          = "migration-staging-alb"
  alb_sg_name       = "migration-staging-alb-sg"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = var.certificate_arn
}

module "ecs" {
  source = "../../modules/ecs"

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

# RDS Community Module

resource "aws_security_group" "rds" {
  name        = "migration-staging-rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.ecs.ecs_security_group_id]
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.1"

  identifier        = "migration-staging-db"
  engine            = "postgres"
  engine_version    = "17.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "migrationdb"
  username = "admin"

  manage_master_user_password = true

  manage_master_user_password_rotation                   = true
  master_user_password_rotation_automatically_after_days = 15


  subnet_ids             = module.vpc.rds_private_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot     = true
  publicly_accessible     = false
  deletion_protection     = false
  backup_retention_period = 1
}


# Monitoring and alerting to be added in Production
