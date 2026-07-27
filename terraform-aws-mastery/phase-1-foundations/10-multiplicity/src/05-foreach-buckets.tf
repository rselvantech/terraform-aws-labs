resource "aws_s3_bucket" "env" {
  for_each = var.environments
  bucket   = "cloudnova-${each.key}-assets"

  tags = {
    Environment = each.key
    Region      = each.value
    ManagedBy   = "terraform-demo-10"
  }
}

resource "aws_iam_user" "svc" {
  for_each = toset(var.cloudnova_iam_users)
  name     = each.key

  tags = {
    ManagedBy = "terraform-demo-10"
  }
}
