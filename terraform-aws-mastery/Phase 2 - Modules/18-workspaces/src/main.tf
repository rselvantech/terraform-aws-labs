resource "aws_s3_bucket" "this" {
  bucket = "cloudnova-${terraform.workspace}-demo18"

  tags = {
    Environment = terraform.workspace
    ManagedBy   = "terraform-demo-18"
  }
}
