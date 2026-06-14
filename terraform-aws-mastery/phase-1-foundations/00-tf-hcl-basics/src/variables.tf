variable "project_name" {
  type        = string
  description = "Name of the project — used in generated filenames"
  default     = "cloudnova"
}

variable "environment" {
  type        = string
  description = "Target deployment environment"
  default     = "dev"

  validation {                    # Terraform rejects invalid values at plan time
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "author" {
  type        = string
  description = "Your name — written into the generated report file"
  default     = "DevOps Engineer"
}
