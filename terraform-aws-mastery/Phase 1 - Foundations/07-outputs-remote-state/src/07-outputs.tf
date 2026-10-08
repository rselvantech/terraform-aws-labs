output "role_name" {
  description = "Name of the IAM deploy role"
  value       = aws_iam_role.deploy.name
}

output "role_arn" {
  description = "ARN of the IAM deploy role"
  value       = aws_iam_role.deploy.arn
  depends_on  = [aws_iam_role_policy.deploy]
}

# Required to be sensitive — the source variable is sensitive, and
# Terraform enforces that the output must be too (Break-Fix Error 1
# shows what happens if you don't).
output "external_secret_label_out" {
  description = "Echoes the sensitive demo variable from Demo 05"
  value       = var.external_secret_label
  sensitive   = true
}

output "sns_topic_arn" {
  description = "ARN of the deploy-notifications SNS topic"
  value       = aws_sns_topic.deploy_notifications.arn
}
