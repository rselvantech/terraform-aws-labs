output "role_name" {
  description = "Name of the IAM deploy role"
  value       = aws_iam_role.deploy.name
}

output "role_arn" {
  description = "ARN of the IAM deploy role"
  value       = aws_iam_role.deploy.arn
}
