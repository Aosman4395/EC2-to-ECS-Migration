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
}

module "ecs" {
  source = "../../modules/ecs"

  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.ecs_private_subnet_ids
  alb_security_group_id = module.alb.alb_sg_id
  target_group_arn      = module.alb.target_group_arn

  execution_role_name = module.iam.execution_role_name
  execution_role_arn  = module.iam.execution_role_arn
  task_role_arn       = module.iam.task_role_arn

  container_name            = var.container_name
  container_port            = var.container_port
  container_image           = var.container_image
  log_group_name            = "/ecs/migration-staging-api"
  aws_region                = var.aws_region
  db_host                   = module.rds.db_instance_address
  db_name                   = module.rds.db_instance_name
  db_port                   = module.rds.db_instance_port
  db_secret_arn             = module.rds.db_instance_master_user_secret_arn
  additional_load_balancers = local.additional_load_balancers
}

# RDS Community Module

resource "aws_security_group" "rds" {
  name        = "migration-staging-rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow PostgreSQL connections from ECS tasks"
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
  engine_version    = "17.11"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "migrationdb"
  username = "migrationuser"

  manage_master_user_password = true

  manage_master_user_password_rotation = false

  create_db_parameter_group = false
  create_db_subnet_group    = true
  subnet_ids                = module.vpc.rds_private_subnet_ids
  vpc_security_group_ids    = [aws_security_group.rds.id]

  skip_final_snapshot     = true
  publicly_accessible     = false
  deletion_protection     = false
  backup_retention_period = 1
}


# SSM parameter for alb
data "aws_ssm_parameters_by_path" "prod_integration" {
  path            = "/ecs-migration/prod/integration/"
  with_decryption = false
}
locals {
  prod_parameters           = zipmap(data.aws_ssm_parameters_by_path.prod_integration.names, nonsensitive(data.aws_ssm_parameters_by_path.prod_integration.values))
  prod_alb                  = lookup(local.prod_parameters, "/ecs-migration/prod/integration/alb", null)
  additional_load_balancers = local.prod_alb == null ? {} : { prod = jsondecode(local.prod_alb) }
}
