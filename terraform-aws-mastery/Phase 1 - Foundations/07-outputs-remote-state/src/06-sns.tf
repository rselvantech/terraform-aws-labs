resource "aws_sns_topic" "deploy_notifications" {
  name   = local.sns_topic_name
  policy = local.sns_topic_policy
  tags   = local.sns_tags
}
