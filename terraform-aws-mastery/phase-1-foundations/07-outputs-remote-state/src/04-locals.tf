data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  role_name   = var.custom_role_name != null ? var.custom_role_name : "${local.name_prefix}-${var.role_purpose}-role"
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  trusted_principals = length(var.trusted_account_ids) > 0 ? [
    for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"
  ] : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAssumeRole"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  permission_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowedActions"
        Effect   = "Allow"
        Action   = var.allowed_actions
        Resource = "*"
      }
    ]
  })

  # try() safely reads the optional description field — see Demo 06 Part B
  role_description = try(
    var.role_config.description,
    "CI/CD deploy role for ${var.project} ${var.environment}"
  )

  # coalesce(): falls through to var.max_session_duration if unset
  effective_max_session = coalesce(
    try(var.role_config.max_session_secs, null),
    var.max_session_duration
  )

  # merge() — caller-supplied extra_tags win on any key conflict
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Demo        = var.demo
      ManagedBy   = "Terraform"
      Owner       = "platform-team"
    },
    var.extra_tags
  )

  # SNS locals — reuse name_prefix, trusted_principals, common_tags from above
  sns_topic_name = "${local.name_prefix}-deploy-notifications"

  sns_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = local.trusted_principals }
        Action    = "sns:Publish"
        Resource  = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sns_topic_name}"
      }
    ]
  })

  sns_tags = merge(local.common_tags, {
    Purpose = "deploy-notifications"
  })
}
