resource "aws_cloudwatch_log_group" "service" {
  for_each          = var.service_config
  name              = "/cloudnova/${each.key}"
  retention_in_days = each.value.retention_days

  tags = {
    Service = each.key
    Tier    = each.value.tier
  }
}
