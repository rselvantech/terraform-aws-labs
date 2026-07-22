resource "aws_cloudwatch_log_metric_filter" "error_count" {
  for_each       = var.service_config
  name           = "${each.key}-error-count"
  log_group_name = aws_cloudwatch_log_group.service[each.key].name
  pattern        = var.error_pattern

  metric_transformation {
    name      = "${each.key}ErrorCount"
    namespace = "CloudNova/Application"
    value     = "1"
  }
}
