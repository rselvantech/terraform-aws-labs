resource "aws_ssm_parameter" "sns_topic_arn" {
  name  = "/cloudnova/${var.environment}/sns-deploy-notifications-arn"
  type  = "SecureString" # encrypted at rest — this value is an ARN, not itself sensitive, but demonstrates the pattern for values that would be
  value = aws_sns_topic.deploy_notifications.arn
  tags  = local.sns_tags
}
