variable "aws_region" {
  type        = string
  description = "AWS region for the state backend"
  default     = "us-east-2"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI named profile for authentication"
  default     = "default"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique name for the project-layer state bucket"
  default     = "tfstate-cloudnova-project-163125980376-us-east-2"
  # Replace the account ID segment with your own account ID
}
