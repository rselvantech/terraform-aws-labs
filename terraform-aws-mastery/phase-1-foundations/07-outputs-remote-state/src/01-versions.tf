terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
  }

  backend "s3" {
    bucket       = "tfstate-cloudnova-163125980376-us-east-2"
    # ↑ replace <account-id> with your own account ID — bucket names
    # must be globally unique, and including the account ID is the
    # usual convention for that
    key          = "phase-1/07-outputs-remote-state/terraform.tfstate"
    # ↑ path within the bucket — keeps every demo's state organized
    # under one bucket, one subfolder per demo
    region       = "us-east-2"
    profile      = "default"
    encrypt      = true
    use_lockfile = true
    # ↑ S3-native locking (Terraform 1.11+) — no DynamoDB table needed
  }
}
