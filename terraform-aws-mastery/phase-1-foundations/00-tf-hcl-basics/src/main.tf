# Provider: hashicorp/random
# Generates a short alphanumeric string stored in state.
# Same value on every apply until explicitly replaced.
resource "random_string" "suffix" {
  length  = 6      # mandatory — how many characters
  upper   = false  # optional — no uppercase (cleaner in filenames)
  special = false  # optional — no special chars (!@#) — safe in filenames
  numeric = true   # optional — include digits
}

# Provider: hashicorp/local
# Creates a text file on the filesystem where Terraform runs.
# Terraform manages the file: plan detects changes, destroy removes it.
resource "local_file" "report" {
  filename        = "${path.module}/output/${local.filename}"
  # path.module = the directory containing this .tf file (Terraform built-in)
  content         = local.file_content
  file_permission = "0644"   # rw-r--r--
  # Implicit dependency: local.filename references random_string.suffix.result
  # → Terraform creates random_string.suffix BEFORE local_file.report
}
