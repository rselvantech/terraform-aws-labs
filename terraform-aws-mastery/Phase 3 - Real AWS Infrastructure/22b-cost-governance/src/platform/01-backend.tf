terraform {
  backend "s3" {
    bucket = "tfstate-cloudnova-project-163125980376-us-east-2"
    # ↑ output from 22a, pasted in as a literal string — a backend
    # block cannot reference var.*/local.*/module outputs, at any
    # Terraform version.

    key = "platform/terraform.tfstate"
    # ↑ everything created once and left standing — this demo's
    # governance resources, plus ECR/ACM (22c) and IAM identity
    # (Demo 24) once built. The workloads config uses a different key
    # in the same bucket, and is never reachable from here.

    region  = "us-east-2"
    profile = "default"
    encrypt = true

    use_lockfile = true
  }
}
