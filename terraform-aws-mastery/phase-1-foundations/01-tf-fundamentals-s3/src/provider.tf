provider "aws" {
  region  = var.aws_region  # which AWS region — us-east-2
  profile = var.aws_profile # named profile from ~/.aws/credentials

  default_tags {
    tags = local.common_tags # applied automatically to every resource
  }
}

provider "random" {} # random provider needs no configuration
