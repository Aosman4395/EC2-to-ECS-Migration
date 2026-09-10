mock_provider "aws" {}
mock_provider "archive" {}

override_data {
  target = data.terraform_remote_state.staging
  values = { outputs = { staging_vpc_id = "vpc-0123456789abcdef0" } }
}
override_data {
  target = data.terraform_remote_state.legacy_dev
  values = { outputs = { ec2_instance_id = "i-0123456789abcdef0" } }
}
override_data {
  target = data.aws_instance.legacy
  values = { ami = "ami-0123456789abcdef0" }
}
override_data {
  target = data.aws_subnets.public
  values = { ids = ["subnet-11111111111111111", "subnet-22222222222222222"] }
}
override_data {
  target = data.aws_subnets.ecs_private
  values = { ids = ["subnet-33333333333333333", "subnet-44444444444444444"] }
}
override_data {
  target = module.alb.data.aws_vpc.platform
  values = { cidr_block = "10.0.0.0/16" }
}

run "initial_routing" {
  command = plan
  assert {
    condition     = output.routing_weights.legacy == 100 && output.routing_weights.ecs == 0
    error_message = "Production must initially send all traffic to legacy."
  }
}
run "reject_zero_total" {
  command = plan
  variables {
    legacy_weight = 0
    ecs_weight    = 0
  }
  expect_failures = [var.ecs_weight]
}
run "reject_fractional_weight" {
  command = plan
  variables {
    legacy_weight = 99.5
    ecs_weight    = 0.5
  }
  expect_failures = [var.legacy_weight]
}

run "reject_fractional_ecs_weight" {
  command = plan
  variables {
    legacy_weight = 99
    ecs_weight    = 0.5
  }
  expect_failures = [var.ecs_weight]
}

run "existing_ecs_without_prod" {
  command = plan
  module { source = "../../modules/ecs" }
  variables {
    vpc_id                = "vpc-0123456789abcdef0"
    subnet_ids            = ["subnet-11111111111111111"]
    target_group_arn      = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/staging/1111111111111111"
    alb_security_group_id = "sg-11111111111111111"
    execution_role_arn    = "arn:aws:iam::123456789012:role/execution"
    execution_role_name   = "execution"
    task_role_arn         = "arn:aws:iam::123456789012:role/task"
    container_name        = "legacy-api"
    container_image       = "example/api:test"
    log_group_name        = "/ecs/test"
    db_host               = "example.internal"
    db_name               = "migrationdb"
    db_port               = 5432
    db_secret_arn         = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:test-123456"
  }
  assert {
    condition     = length(aws_ecs_service.api_service.load_balancer) == 1
    error_message = "Existing staging ALB must remain when prod is absent."
  }
}

run "existing_ecs_with_prod" {
  command = plan
  module { source = "../../modules/ecs" }
  variables {
    vpc_id                = "vpc-0123456789abcdef0"
    subnet_ids            = ["subnet-11111111111111111"]
    target_group_arn      = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/staging/1111111111111111"
    alb_security_group_id = "sg-11111111111111111"
    execution_role_arn    = "arn:aws:iam::123456789012:role/execution"
    execution_role_name   = "execution"
    task_role_arn         = "arn:aws:iam::123456789012:role/task"
    container_name        = "legacy-api"
    container_image       = "example/api:test"
    log_group_name        = "/ecs/test"
    db_host               = "example.internal"
    db_name               = "migrationdb"
    db_port               = 5432
    db_secret_arn         = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:test-123456"
    additional_load_balancers = {
      prod = {
        target_group_arn      = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/prod/2222222222222222"
        alb_security_group_id = "sg-22222222222222222"
      }
    }
  }
  assert {
    condition     = length(aws_ecs_service.api_service.load_balancer) == 2 && length(aws_security_group_rule.additional_albs) == 1
    error_message = "Prod must add a target group and its ingress rule without removing staging."
  }
}
