output "log_group_names" {
  description = "Names of all created log groups"
  value       = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
}
