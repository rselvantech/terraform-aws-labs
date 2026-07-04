# Outputs added in Part B once aws_s3_bucket.uploads exists
output "legacy_bucket_name" {
  description = "Name of the imported legacy bucket"
  value       = aws_s3_bucket.uploads.bucket
}

output "legacy_bucket_arn" {
  description = "ARN of the imported legacy bucket"
  value       = aws_s3_bucket.uploads.arn
}