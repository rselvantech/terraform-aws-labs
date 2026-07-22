data "aws_s3_bucket" "legacy" {
  count  = var.legacy_bucket_name != "" ? 1 : 0
  bucket = var.legacy_bucket_name
}
