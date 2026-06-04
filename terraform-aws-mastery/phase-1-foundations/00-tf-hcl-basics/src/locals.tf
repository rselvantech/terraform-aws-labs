locals {
  # Level 1 — primitive values
  project     = var.project_name
  environment = var.environment

  # Level 2 — composite values built from level 1
  # random_string.suffix.result is a resource attribute reference
  # this shows cross-resource referencing — the file depends on the random string
  filename = "${local.project}-${local.environment}-${random_string.suffix.result}.txt"

  # Level 3 — the content written into the file
  # templatefile() would be used here in production; heredoc used for clarity
  file_content = <<-EOT
    ┌──────────────────────────────────────────────┐
    │  CloudNova Infrastructure Report             │
    ├──────────────────────────────────────────────┤
    │  Project     : ${local.project}
    │  Environment : ${local.environment}
    │  Generated   : by Terraform
    │  Author      : ${var.author}
    │  Unique ID   : ${random_string.suffix.result}
    └──────────────────────────────────────────────┘

    This file was created by Terraform.
    It was NOT created by hand — it is 100% reproducible.

    Run 'terraform destroy' then 'terraform apply' again and you get
    a new unique ID but the same structure. That is IaC.
  EOT
}
