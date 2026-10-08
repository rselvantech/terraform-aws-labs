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

  name = "cloudnova-broken-demo16"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b"]
  public_subnets  = ["10.0.1.0/24"]              # Error 1: only 1 entry, azs has 2
  private_subnets = ["10.5.11.0/24", "10.0.12.0/24"] # Error 2: 10.5.11.0/24 is outside the VPC's 10.0.0.0/16 range
}

output "vpc_identifier" {
  value = module.vpc.id # Error 3: wrong output name (should be vpc_id)
}
