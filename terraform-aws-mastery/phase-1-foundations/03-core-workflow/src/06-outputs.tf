output "topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.deployments.arn
}

output "queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.notifications.arn
}

output "queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.notifications.id
}

output "random_suffix" {
  description = "Random hex suffix used in resource names"
  value       = random_id.suffix.hex
}
