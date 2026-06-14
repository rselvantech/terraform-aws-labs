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

provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

resource "aws_s3_bucket" "primary" {
  bucket = "cloudnova-primary-demo"
}

resource "aws_s3_bucket" "archive" {
  bucket   = "cloudnova-archive-demo"
  provider = aws.east              # Error 1
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket   = aws_s3_bucket.archive.id
                                   # Error 2 — missing provider assignment
  versioning_configuration {
    status = "enabled"             # Error 3
  }
}
