variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-2"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI named profile for authentication"
  default     = "default"
}

variable "service_config" {
  type = map(object({
    retention_days = number
    tier           = string
  }))
  description = "Per-service configuration — retention and criticality tier"
  default = {
    auth = {
      retention_days = 30
      tier           = "critical"
    }
    billing = {
      retention_days = 90
      tier           = "critical"
    }
    notifications = {
      retention_days = 14
      tier           = "standard"
    }
  }
}

variable "error_pattern" {
  type        = string
  description = "CloudWatch Logs filter pattern for the metric filter"
  default     = "ERROR"
}
