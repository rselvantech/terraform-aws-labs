terraform {
  required_version = "~> 1.15.0"   # Terraform CLI must be 1.15.x

  required_providers {
    local = {
      source  = "hashicorp/local"   # registry.terraform.io/hashicorp/local
      version = "~> 2.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}
# No provider {} blocks needed — local and random require no configuration
