data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  role_name   = var.custom_role_name != null ? var.custom_role_name : "${local.name_prefix}-${var.role_purpose}-role"
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  # for expression (preview — full coverage Demo 09): builds one principal
  # ARN per trusted account ID, or falls back to self-trust if the list is empty
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

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Demo        = var.demo
      ManagedBy   = "Terraform"
      Owner       = "platform-team"
    },
    var.extra_tags # rightmost — caller overrides win
  )

  # try() safely reads the optional description field — var.role_config.description
  # can genuinely be null (no default was given for it in 03-variables.tf),
  # so try() catches that and falls through to a computed default
  role_description = try(
    var.role_config.description,
    "CI/CD deploy role for ${var.project} ${var.environment}"
  )

  # coalesce(): try() extracts max_session_secs (which, unlike description,
  # already has its own default of 3600 from optional() — so this try()
  # is a defensive no-op here, and coalesce() falls through to
  # var.max_session_duration only if try() itself somehow returned null)
  effective_max_session = coalesce(
    try(var.role_config.max_session_secs, null),
    var.max_session_duration
  )

}
