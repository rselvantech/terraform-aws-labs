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

# Error 1: for_each given a duplicate-key map
resource "aws_s3_bucket" "env" {
  for_each = {
    dev  = "us-east-2"
    test = "us-west-2"
  }
  bucket = "cloudnova-${each.key}-broken"
}

# Error 2: count and for_each on the same resource
resource "aws_sqs_queue" "dlq" {
  # count    = 2
  for_each = toset(["a", "b"])
  name     = "cloudnova-broken-dlq"
}

# Error 3: count.index referenced inside a for_each resource
resource "aws_iam_user" "svc" {
  for_each = toset(["dev-readonly", "billing-auditor"])
  # name     = "svc-user-${count.index}"
  name = "svc-user-${each.value}"

}

# Error 4: wrong dynamic iterator reference after renaming it
resource "aws_security_group" "broken" {
  name = "cloudnova-broken-sg"

  dynamic "ingress" {
    for_each = ["443", "22"]
    # iterator = rule
    content {
      from_port = ingress.value # should be rule.value — iterator was renamed
      to_port   = ingress.value
      protocol  = "tcp"
    }
  }
}
