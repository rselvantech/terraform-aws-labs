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

variable "db_password" {
  type      = string
  sensitive = true
  default   = "demo-password-value"
}

variable "session_token" {
  type      = string
  ephemeral = true
  default   = "demo-token"
}

# Error 1: exposes a sensitive variable through a non-sensitive output
output "db_password_leak" {
  value = var.db_password
}

# Error 2: ephemeral output in the root module
output "session_token_echo" {
  value     = var.session_token
  ephemeral = true
}

resource "aws_ssm_parameter" "leaked_arn" {
  name  = "/cloudnova/demo/leaked-value"
  type  = "String" # Error 3 — should be SecureString
  value = var.db_password
}
