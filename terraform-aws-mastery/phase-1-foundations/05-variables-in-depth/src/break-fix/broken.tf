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
  region  = "us-east-2"
  profile = "default"
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = "dev"                             # Error 1
    error_message = "Must be dev, staging, or prod."
  }
}

variable "retry_count" {
  type    = number
  default = 3
}

variable "custom_role_name" {
  type     = string
  default  = "cloudnova-fallback-role"
  nullable = false                                     # Error 2 setup — see below
}

output "retry_as_string" {
  value = var.retry_count + "extra"                     # Error 3
}

output "custom_role_name" {
  value = var.custom_role_name                          # needed to observe Error 2
}
