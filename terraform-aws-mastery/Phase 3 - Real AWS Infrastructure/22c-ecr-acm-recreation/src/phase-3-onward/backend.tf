terraform {
  backend "s3" {
    bucket       = "tfstate-cloudnova-project-163125980376-us-east-2"
    key          = "phase-3-onward/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}
