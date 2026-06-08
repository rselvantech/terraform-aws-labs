locals {
  # Globally unique bucket name — e.g. "cloudnova-dev-app-a1b2c3d4"
  # random_id.suffix.hex is a cross-resource reference:
  # Terraform creates random_id.suffix BEFORE aws_s3_bucket.app
  bucket_name = "${var.project}-${var.environment}-app-${random_id.suffix.hex}"

  # Tag map — passed to provider default_tags
  # Applied automatically to every resource this provider creates
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}
