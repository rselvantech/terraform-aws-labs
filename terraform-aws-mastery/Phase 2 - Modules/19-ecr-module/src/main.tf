module "ecr" {
  for_each = toset(local.services)

  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name                 = "cloudnova-retail-${each.key}"
  repository_image_tag_mutability = "IMMUTABLE"
  repository_force_delete         = true

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = {
    ManagedBy = "terraform-demo-19"
    Service   = each.key
  }
}
