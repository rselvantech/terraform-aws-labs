terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0" # v6 — standalone S3 resource pattern
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0" # for unique bucket name suffix
    }
  }
}
