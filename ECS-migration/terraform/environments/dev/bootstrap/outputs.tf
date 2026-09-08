output "github_actions_legacy_role_arn" {
  description = "IAM role for legacy GitHub Actions deployments"
  value       = aws_iam_role.github_actions_legacy.arn
}
