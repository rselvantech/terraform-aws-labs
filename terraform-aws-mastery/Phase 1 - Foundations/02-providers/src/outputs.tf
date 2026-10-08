output "primary_bucket_name" {
  description = "Name of the primary bucket (us-east-2)"
  value       = aws_s3_bucket.primary.bucket
}

output "primary_bucket_region" {
  description = "Region of the primary bucket"
  value       = aws_s3_bucket.primary.region
}

output "archive_bucket_name" {
  description = "Name of the archive bucket (us-west-2)"
  value       = aws_s3_bucket.archive.bucket
}

output "archive_bucket_region" {
  description = "Region of the archive bucket"
  value       = aws_s3_bucket.archive.region
}
