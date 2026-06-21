terraform {
  backend "s3" {
    bucket       = "tfstate-cloudnova-163125980376-us-east-2"
    # ↑ reuse the same state bucket from Demo 01, or create a fresh one —
    # replace with your actual state bucket name

    key          = "phase-1/04-state-management/terraform.tfstate"
    region       = "us-east-2"
    profile      = "default"
    encrypt      = true
    use_lockfile = true
  }
}
