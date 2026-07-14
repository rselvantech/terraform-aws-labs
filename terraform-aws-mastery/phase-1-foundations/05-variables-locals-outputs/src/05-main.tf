resource "aws_iam_role" "deploy" {
  name                 = local.role_name
  description          = "CI/CD deploy role for ${var.project} ${var.environment}"
  assume_role_policy   = local.trust_policy
  max_session_duration = var.max_session_duration
  tags                 = local.role_tags
}

resource "aws_iam_role_policy" "deploy" {
  name   = local.policy_name
  role   = aws_iam_role.deploy.name
  policy = local.permission_policy
}
