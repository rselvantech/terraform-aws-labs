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

# Error 1: wrong policy name (typo)
data "aws_iam_policy" "broken_policy" {
  name = "AmazonS3ReadOnlyAccess" # missing final 's'
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Error 2: attribute typo — .image_name doesn't exist, the real attribute is .name
output "ami_name" {
  value = data.aws_ami.amazon_linux_2023.image_id
}

variable "legacy_bucket_name" {
  type    = string
  default = "cloudnova-legacy-uploads"
}

data "aws_s3_bucket" "legacy" {
  count  = var.legacy_bucket_name != "" ? 1 : 0
  bucket = var.legacy_bucket_name
}

# Error 3: unguarded index — errors when legacy_bucket_name is left at its default ""
output "legacy_bucket_arn" {
  value = length(data.aws_s3_bucket.legacy) > 0 ? data.aws_s3_bucket.legacy[0].arn : 0
}
