locals {
  # Reused from the IAM role's locals — proves name_prefix isn't role-specific
  sns_topic_name = "${local.name_prefix}-deploy-notifications"

  # A resource policy (who can publish to this topic) — same jsonencode()
  # pattern as the IAM trust policy, different statement shape
  sns_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals } # reused — same list as the IAM trust policy
        Action    = "sns:Publish"
        Resource  = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sns_topic_name}"
      }
    ]
  })

  # merge() again — same pattern as the IAM role's tags (Part B, Step 4),
  # but this resource gets ONE EXTRA tag (Purpose) that the IAM role does
  # not — this is why the two resources' tag sets differ by one entry
  sns_tags = merge(local.common_tags, {
    Purpose = "deploy-notifications"
  })
}

resource "aws_sns_topic" "deploy_notifications" {
  name   = local.sns_topic_name
  policy = local.sns_topic_policy
  tags   = local.sns_tags
}
