data "terraform_remote_state" "staging" {
  backend = "s3"
  config = {
    bucket = "aosman-ecs-bootstrap-bucket"
    key    = "environments/staging/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "legacy_dev" {
  backend = "s3"
  config = {
    bucket = "aosman-ecs-bootstrap-bucket"
    key    = "environments/dev/terraform.tfstate"
    region = var.aws_region
  }
}

# Reuse legacy AMI
data "aws_instance" "legacy" {
  instance_id = data.terraform_remote_state.legacy_dev.outputs.ec2_instance_id
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.staging.outputs.staging_vpc_id]
  }
  filter {
    name   = "cidr-block"
    values = ["10.0.1.0/24", "10.0.2.0/24"]
  }
}

data "aws_subnets" "ecs_private" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.staging.outputs.staging_vpc_id]
  }
  filter {
    name   = "cidr-block"
    values = ["10.0.11.0/24", "10.0.12.0/24"]
  }
}

module "alb" {
  source            = "../../modules/migration-alb"
  name              = "migration-prod-alb"
  vpc_id            = data.terraform_remote_state.staging.outputs.staging_vpc_id
  public_subnet_ids = sort(data.aws_subnets.public.ids)
  legacy_weight     = var.legacy_weight
  ecs_weight        = var.ecs_weight
}

module "legacy" {
  source                = "../../modules/legacy-runtime"
  name                  = "migration-prod-legacy"
  vpc_id                = data.terraform_remote_state.staging.outputs.staging_vpc_id
  subnet_id             = sort(data.aws_subnets.ecs_private.ids)[0]
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.legacy_target_group_arn
  ami_id                = data.aws_instance.legacy.ami
  instance_type         = var.legacy_instance_type
  aws_region            = var.aws_region
  app_source_dir        = abspath("${path.module}/../../../../legacy-app")
  archive_path          = "${path.module}/app.zip"
}

# SSM parameter for alb
resource "aws_ssm_parameter" "ecs_integration" {
  name = "/ecs-migration/prod/integration/alb"
  type = "String"
  value = jsonencode({
    target_group_arn      = module.alb.ecs_target_group_arn
    alb_security_group_id = module.alb.security_group_id
  })
  depends_on = [module.alb]
}
