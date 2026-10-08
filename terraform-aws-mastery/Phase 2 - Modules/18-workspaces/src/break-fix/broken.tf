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

resource "aws_s3_bucket" "this" {
  bucket = "cloudnova-demo18-broken" # Error 1: no ${terraform.workspace} interpolation at all

  tags = {
    Environment = terraform.workspce # Error 2: typo, "workspce" instead of "workspace"
  }
}
