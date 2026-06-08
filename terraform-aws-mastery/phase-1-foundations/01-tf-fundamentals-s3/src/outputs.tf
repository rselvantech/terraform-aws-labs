output "bucket_name" {
  description = "Name of the app S3 bucket"
  value       = aws_s3_bucket.app.bucket
}

output "bucket_arn" {
  description = "ARN of the app S3 bucket"
  value       = aws_s3_bucket.app.arn
}

output "bucket_region" {
  description = "AWS region where the bucket was created"
  value       = aws_s3_bucket.app.region
}

output "random_suffix" {
  description = "Random hex suffix used in the bucket name"
  value       = random_id.suffix.hex
}
