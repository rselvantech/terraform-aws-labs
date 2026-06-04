# broken.tf — DO NOT COPY VERBATIM — find and fix the errors

terraform {
  required_version = "~> 1.15.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}

variable "team" {
  type    = string
  default = "platform"
}

variable "env" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.env)     # Error 1
    error_message = "Must be dev or prod."
  }
}

resource "random_string" "id" {
  length  = 8
  upper   = false                                       # Error 2
  special = false
}

output "team_id" {
  value = "${var.team}-${random_string.id.result}"             # Error 3
}
