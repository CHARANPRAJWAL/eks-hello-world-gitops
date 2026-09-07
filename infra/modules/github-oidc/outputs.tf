output "ci_role_arn" {
  description = "ARN of the CI role to set as the GitHub Actions variable AWS_CI_ROLE_ARN."
  value       = aws_iam_role.ci.arn
}
