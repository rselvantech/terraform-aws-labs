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

variable "legacy_bucket_name" {
  type        = string
  description = "Name of a pre-existing S3 bucket to conditionally read. Empty string = skip entirely."
  default     = ""
}

variable "s3_policy_name" {
  type        = string
  description = "Name of the AWS-managed S3 policy to read"
  default     = "AmazonS3ReadOnlyAccess"
}

variable "ec2_policy_name" {
  type        = string
  description = "Name of the AWS-managed EC2 policy to read"
  default     = "AmazonEC2ReadOnlyAccess"
}
