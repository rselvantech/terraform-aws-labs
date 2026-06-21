locals {
  # Unique names — e.g. "cloudnova-dev-deployments-a1b2c3d4"
  topic_name = "${var.project}-${var.environment}-deployments-${random_id.suffix.hex}"
  queue_name = "${var.project}-${var.environment}-notifications-${random_id.suffix.hex}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Demo        = var.demo
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}
