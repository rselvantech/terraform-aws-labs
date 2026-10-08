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

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name            = "cloudnova-broken-demo17"
  cidr            = "10.0.0.0/16"
  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
}

locals {
  tiers = {
    web = { port = 443, cidr = "0.0.0.0/0" }
    app = { port = 8080, cidr = "10.0.0.0/16" }
  }
}

module "tier_sg" {
  for_each = local.tiers

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "cloudnova-${each.key}-tier-sg"
  description = "Security group for the ${each.key} tier"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    tier_access = {
      from_port   = each.valeu.port # Error 1: typo, "valeu" instead of "value"
      to_port     = each.value.port
      ip_protocol = "tcp"
      cidr_ipv4   = each.value.cidr
    }
  }
}

output "web_sg_id" {
  value = module.tier_sg.id # Error 2: missing instance key
}

output "db_sg_id" {
  value = module.tier_sg["db"].id # Error 3: "db" isn't a key in local.tiers
}
