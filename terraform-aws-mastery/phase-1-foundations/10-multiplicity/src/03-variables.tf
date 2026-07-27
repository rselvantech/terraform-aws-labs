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

variable "dlq_count" {
  type        = number
  description = "Number of dead-letter queues to create via count"
  default     = 3
}

variable "environments" {
  type        = map(string)
  description = "CloudNova environments to provision a bucket for, keyed by name"
  default = {
    dev     = "us-east-2"
    staging = "us-east-2"
    prod    = "us-east-2"
  }
}

variable "cloudnova_iam_users" {
  type        = list(string)
  description = "Read-only IAM users to create — a list, converted to a set for for_each"
  default     = ["dev-readonly", "billing-auditor"]
}

variable "ingress_rules" {
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  description = "Ingress rules for the app security group — variable count, drives the dynamic block"
  default = [
    {
      description = "HTTPS from anywhere"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "SSH from CloudNova office"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["203.0.113.0/24"]
    }
  ]
}
