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

data "aws_route53_zone" "this" {
  name = "rselvantech.con." # Error 1: typo, ".con" instead of ".com"
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.0"

  domain_name = "broken-demo20.rselvantech.com"
  zone_id     = data.aws_route53_zone.this.zone_id

  validation_method   = "DSN" # Error 2: typo, should be "DNS"
  wait_for_validation = true
}

output "cert_arn" {
  value = module.acm.arn # Error 3: wrong output name (should be certificate_arn)
}
