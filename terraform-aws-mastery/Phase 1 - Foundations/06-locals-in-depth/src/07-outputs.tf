output "role_name" {
  description = "Name of the IAM deploy role"
  value       = aws_iam_role.deploy.name
}

output "role_arn" {
  description = "ARN of the IAM deploy role"
  value       = aws_iam_role.deploy.arn
}

output "sns_topic_arn" {
  description = "ARN of the deploy-notifications SNS topic"
  value       = aws_sns_topic.deploy_notifications.arn
}
