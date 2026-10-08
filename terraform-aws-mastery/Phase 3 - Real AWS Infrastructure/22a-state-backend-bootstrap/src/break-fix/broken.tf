terraform {
  required_version = "~> 1.15.0"

  backend "s3" {
    bucket       = var.state_bucket_name   # Error
    key          = "break-fix/terraform.tfstate"
    region       = "us-east-2"
    profile      = "default"
    use_lockfile = true
  }
}

variable "state_bucket_name" {
  type    = string
  default = "tfstate-cloudnova-project-163125980376-us-east-2"
}
