locals {
  # Single suffix shared by both buckets — makes pairing clear
  # e.g. cloudnova-dev-primary-a1b2c3d4 + cloudnova-dev-archive-a1b2c3d4
  primary_bucket_name = "${var.project}-${var.environment}-primary-${random_id.suffix.hex}"
  archive_bucket_name = "${var.project}-${var.environment}-archive-${random_id.suffix.hex}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}
