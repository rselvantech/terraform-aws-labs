output "dlq_arns" {
  description = "ARNs of all CloudNova notification DLQs, collected via splat expression"
  value       = aws_sqs_queue.dlq[*].arn
}
