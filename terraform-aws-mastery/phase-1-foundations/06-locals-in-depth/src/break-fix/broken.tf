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

locals {
  # Error 1: circular reference
  a = "prefix-${local.b}"
  b = "suffix-${local.a}"

  # Error 2: attempting a type argument on a local (not valid HCL for locals)
  c = {
    type  = string   # locals have no type argument — this is just a map key
    value = "test"
  }

  base_tags = {
    Owner = "platform-team"
  }
  caller_tags = {
    Owner = "devops-team"
  }
  # Error 3: merge() argument order reversed — base wins instead of caller
  common_tags = merge(local.caller_tags, local.base_tags)
}

output "common_tags_result" {
  value = local.common_tags
}
