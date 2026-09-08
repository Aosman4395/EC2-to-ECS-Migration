# Existing GitHub OIDC provider

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM role for Legacy GitHub Actions

resource "aws_iam_role" "github_actions_legacy" {
  name = "github-actions-legacy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Aosman4395@235475597/EC2-to-ECS-Migration@1353647365:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_legacy_admin" {
  role       = aws_iam_role.github_actions_legacy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}