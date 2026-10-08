terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.47.0"
    }
  }
  # No backend block — this config uses local state deliberately.
  # It creates the backend that OTHER configs will use; it can't use
  # a backend it hasn't created yet itself.
}
