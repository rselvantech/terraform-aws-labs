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

variable "secret_token" {
  type      = string
  default   = "my-token"
  sensitive = true
}

output "token_display" {
  description = "The token value for display"
  value       = var.secret_token                     # Error 2
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket  = "tfstate-cloudnova-163125980376-us-east-2"
    key     = "phase-1/05-variables-locals-outputs/terraform.tfstate"
    region  = "us-east-2"
    profile = "default"
  }
}

output "remote_role" {
  value = data.terraform_remote_state.iam.outputs.role_nam   # Error 3
}
