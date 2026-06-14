terraform {
  backend "s3" {
    bucket  = "tfstate-cloudnova-163125980376-us-east-2"
    # ↑ the state bucket you just created in Step 8
    # replace with your actual state bucket name

    key     = "phase-1/01-tf-fundamentals-s3/terraform.tfstate"
    # ↑ path within the bucket — like a folder/filename
    # convention: phase/demo-name/terraform.tfstate
    # keeps multiple demos organised in one state bucket

    region  = "us-east-2"
    profile = "default"
    encrypt = true          # encrypt state file at rest in S3

    use_lockfile = true     # S3 native locking — creates .tfstate.tflock file
                            # no DynamoDB table needed
                            # fully supported in Terraform 1.11+
  }
}
