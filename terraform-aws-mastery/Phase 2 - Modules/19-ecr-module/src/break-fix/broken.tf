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

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name                 = "cloudnova-broken-demo19"
  repository_image_tag_mutability = "IMMUTBLE" # Error 1: typo, should be "IMMUTABLE"

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        # Error 2: missing required "action" block
      }
    ]
  })
}

output "repo_arn" {
  value = module.ecr.repo_arn # Error 3: wrong output name (should be repository_arn)
}
