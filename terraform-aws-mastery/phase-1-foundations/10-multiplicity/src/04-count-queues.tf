resource "aws_sqs_queue" "dlq" {
  count = var.dlq_count
  name  = "cloudnova-notifications-dlq-${count.index}"

  tags = {
    Environment = "shared"
    ManagedBy   = "terraform-demo-10"
  }
}
