output "current_workspace" {
  value       = terraform.workspace
  description = "Which workspace this apply ran against"
}

output "bucket_name" {
  value       = aws_s3_bucket.this.bucket
  description = "Name of the bucket created in the current workspace"
}
