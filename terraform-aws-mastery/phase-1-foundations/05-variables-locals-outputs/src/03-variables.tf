# ── Provider configuration ─────────────────────────────────────────────────

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-2"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI named profile for authentication"
  default     = "default"
}

# ── Project identity ───────────────────────────────────────────────────────

variable "project" {
  type        = string
  description = "Project name — used in resource names and tags"
  default     = "cloudnova"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.project))
    error_message = "project must be 3–20 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "demo" {
  type        = string
  description = "Demo identifier — used in tags for traceability"
  default     = "05-variables-locals-outputs"
}

# ── Role configuration ─────────────────────────────────────────────────────

variable "role_purpose" {
  type        = string
  description = "Short purpose label for the IAM role — becomes part of the role name"
  default     = "deploy"

  validation {
    condition     = length(var.role_purpose) <= 20 && can(regex("^[a-z][a-z0-9-]*$", var.role_purpose))
    error_message = "role_purpose must be lowercase alphanumeric or hyphens, max 20 characters."
  }
}

variable "trusted_account_ids" {
  type        = list(string)
  description = "List of AWS account IDs allowed to assume this role. Empty list = self-trust (current account only)."
  default     = []

  validation {
    condition     = alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "All trusted_account_ids must be 12-digit AWS account IDs."
  }
}

variable "allowed_actions" {
  type        = list(string)
  description = "IAM actions this role is permitted to perform"
  default     = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
}

variable "custom_role_name" {
  type        = string
  description = "Optional: override the computed role name. If null, a name is computed from project+environment+purpose."
  default     = null
  nullable    = true
}

# ── Sensitive and ephemeral demonstration ──────────────────────────────────

variable "external_secret_label" {
  type        = string
  description = "A label for an external secret — sensitive, stored in state but redacted from output"
  default     = "demo-secret-label"
  sensitive   = true
}

# NOTE: ephemeral variables cannot be used in regular resource arguments.
# var.session_token is demonstrated in Step 11 but NOT referenced in any
# resource argument — it can only flow to an ephemeral output (child module
# only) or a write-only resource argument (Demo 08).
variable "session_token" {
  type        = string
  description = "A short-lived token — ephemeral, never written to state"
  default     = "demo-session-token"
  ephemeral   = true
}

# ── Role instance configuration ────────────────────────────────────────────

variable "max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds (3600–43200)"
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 (1 hour) and 43200 (12 hours)."
  }
}
