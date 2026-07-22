terraform {
  required_version = "~> 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

variable "service_config" {
  type = map(object({
    retention_days = number
  }))
  default = {
    auth    = { retention_days = 30 }
    billing = { retention_days = 90 }
  }
}

locals {
  # Error 1: [] brackets used, but => makes this a map-producing expression
  wrong_brackets = [for name, config in var.service_config : name => config.retention_days]

  # Error 2: single loop variable on a map — only gets the key, not the value
  service_names_only = [for name in var.service_config : name]

  # Error 3: lookup() missing the required default argument
  missing_service = lookup(local.wrong_brackets, "archive")
}
