output "state_bucket_name" {
  description = "Name of the S3 bucket created for project-layer state"
  value       = aws_s3_bucket.state.bucket
}
