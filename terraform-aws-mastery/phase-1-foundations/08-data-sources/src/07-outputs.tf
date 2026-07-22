output "current_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "s3_read_only_policy_arn" {
  description = "ARN of the AWS-managed S3 read-only policy"
  value       = data.aws_iam_policy.s3_read_only.arn
}

output "latest_al2023_ami_id" {
  description = "Latest Amazon Linux 2023 AMI ID in this region"
  value       = data.aws_ami.amazon_linux_2023.id
}

output "latest_al2023_ami_creation_date" {
  description = "Creation date of the resolved AMI, to confirm it's genuinely current"
  value       = data.aws_ami.amazon_linux_2023.creation_date
}
