# Data source — current AWS account ID, used in trust policy self-trust fallback
data "aws_caller_identity" "current" {}

locals {
  # ── Step 1: name prefix ───────────────────────────────────────────────────
  name_prefix = "${var.project}-${var.environment}"

  # ── Step 2: role and policy names ────────────────────────────────────────
  # coalesce(): if var.custom_role_name is null (default), use the computed name
  role_name   = coalesce(var.custom_role_name, "${local.name_prefix}-${var.role_purpose}-role")
  policy_name = "${local.name_prefix}-${var.role_purpose}-policy"

  # ── Step 3: trust policy — who can assume this role ──────────────────────
  # Expression breakdown:
  #   length(var.trusted_account_ids) > 0
  #     → conditional operator: if the list has at least one element...
  #   ? [for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"]
  #     → for expression: transform each account ID into a principal ARN
  #   : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
  #     → fallback: self-trust using the current account's ID
  #
  # Result when trusted_account_ids = ["123456789012"]:
  #   ["arn:aws:iam::123456789012:root"]
  # Result when trusted_account_ids = [] (default — self-trust):
  #   ["arn:aws:iam::163125980376:root"]
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

  # ── Step 4: permission policy — what this role can do ────────────────────
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

  # ── Step 5: common tags — merged with resource-specific tags ─────────────
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }

  # ── Step 6: role-specific tags — merge() adds Purpose on top of common ─────
  role_tags = merge(local.common_tags, {
    Purpose = var.role_purpose
  })
}
