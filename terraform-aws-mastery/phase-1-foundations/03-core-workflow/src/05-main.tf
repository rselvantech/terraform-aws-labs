resource "random_id" "suffix" {
  byte_length = 4   # 4 bytes = 8 hex characters
}

# ── SNS topic ──────────────────────────────────────────────────────────────
# The notification hub — CloudNova publishes deployment/alert events here
resource "aws_sns_topic" "deployments" {
  name = local.topic_name
}

# ── SQS queue ─────────────────────────────────────────────────────────────
# The durable inbox — messages wait here for a consumer to poll
resource "aws_sqs_queue" "notifications" {
  name                       = local.queue_name
  message_retention_seconds = 86400   # 1 day — default is 4 days
}

# ── Queue policy ────────────────────────────────────────────────────────────
# Grants the SNS topic permission to deliver messages to this queue.
# Without this, the subscription is created but messages silently fail
# to arrive — SNS would get an access-denied response from SQS.
resource "aws_sqs_queue_policy" "notifications" {
  queue_url = aws_sqs_queue.notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSDelivery"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.notifications.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.deployments.arn
          }
        }
      }
    ]
  })
}

# ── Subscription ────────────────────────────────────────────────────────────
# Connects the queue to the topic — every message published to the topic
# is delivered into the queue (once the queue policy above allows it)
resource "aws_sns_topic_subscription" "queue" {
  topic_arn = aws_sns_topic.deployments.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notifications.arn   # ARN, not URL, for SQS protocol

  depends_on = [aws_sqs_queue_policy.notifications]   # see explanation below
}
