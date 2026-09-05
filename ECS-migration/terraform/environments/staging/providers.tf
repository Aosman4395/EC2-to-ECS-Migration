terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.27.0"
    }
  }

  backend "s3" {
    bucket       = "aosman-ecs-migration-tf-state"
    key          = "environments/staging/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ec2-to-ecs-migration"
      Environment = "staging"
      ManagedBy   = "Terraform"
    }
  }
}
