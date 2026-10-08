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

# Reads the main configuration's ENTIRE state file, read-only — this
# consuming configuration never touches the main config's .tf files
# or its ability to apply, only the outputs already recorded in state.
data "terraform_remote_state" "outputs_demo" {
  backend = "s3"
  config = {
    bucket = "tfstate-cloudnova-163125980376-us-east-2"
    key    = "phase-1/07-outputs-remote-state/terraform.tfstate"
    region = "us-east-2"
  }
}

output "consumed_role_arn" {
  description = "role_arn read back from the main configuration's state"
  value       = data.terraform_remote_state.outputs_demo.outputs.role_arn
}

output "consumed_sns_arn" {
  description = "sns_topic_arn read back from the main configuration's state"
  value       = data.terraform_remote_state.outputs_demo.outputs.sns_topic_arn
}
