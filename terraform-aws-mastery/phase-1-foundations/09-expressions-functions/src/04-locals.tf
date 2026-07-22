locals {
  # list→list: just the service names
  service_names = [for name, config in var.service_config : name]

  # list→map: service name to full log group name
  log_group_names = {for name, config in var.service_config : name => "cloudnova-${name}-logs"}

  # map→map: just retention days per service
  retention_by_service = {for name, config in var.service_config : name => config.retention_days}

  # filtering with if: only critical-tier services
  critical_services = [for name, config in var.service_config : name if config.tier == "critical"]

  # inverting: retention days back to service name (assumes unique retention values)
  service_by_retention = {for name, config in var.service_config : config.retention_days => name}

  # grouping by computed key: services grouped by tier
  services_by_tier = {for name, config in var.service_config : config.tier => name...}
}
