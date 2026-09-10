terraform {
  required_version = ">= 1.11.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  backend "s3" {
    bucket       = "aosman-ecs-bootstrap-bucket"
    key          = "environments/prod/terraform.tfstate"
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
      Environment = "prod"
      ManagedBy   = "Terraform"
    }
  }
}
