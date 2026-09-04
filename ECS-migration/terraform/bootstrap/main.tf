#S3 bucket 

resource "aws_s3_bucket" "bootstrap_bucket" {
  bucket = "aosman-ecs-bootstrap-bucket"
  force_destroy = false

  tags = {
    Name        = "ECS Bootstrap Bucket"
    Environment = "Bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tf_state_versioning" {
    bucket = aws_s3_bucket.bootstrap_bucket.id
    
    versioning_configuration {
        status = "Enabled"
    }
  
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_encryption" {
    bucket = aws_s3_bucket.bootstrap_bucket.id

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_public_access_block" {
  bucket                  = aws_s3_bucket.bootstrap_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#ECR repository

module "ecr" {
  source = "../modules/ecr"

  ecr_repository_name = var.ecr_repository_name
  ecr_repository_tags = var.ecr_repository_tags
  }

#IAM role for GitHub Actions

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:Aosman4395/EC2-to-ECS-Migration:ref:refs/heads/main",
              "repo:Aosman4395/EC2-to-ECS-Migration:environment:production"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}