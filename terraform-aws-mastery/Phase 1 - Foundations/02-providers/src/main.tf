resource "random_id" "suffix" {
  byte_length = 4
}

# ── Primary bucket — us-east-2 (default provider) ─────────────────────────
resource "aws_s3_bucket" "primary" {
  bucket        = local.primary_bucket_name
  force_destroy = true   # demo only

  tags = { Name = local.primary_bucket_name }
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration { status = "Enabled" }
  depends_on = [aws_s3_bucket.primary]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
  depends_on = [aws_s3_bucket.primary]
}

resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.primary]
}

# ── Archive bucket — us-west-2 (aliased provider) ─────────────────────────
# provider = aws.west routes ALL API calls for this resource to us-west-2
# Without this meta-argument, the bucket would be created in us-east-2
resource "aws_s3_bucket" "archive" {
  bucket        = local.archive_bucket_name
  force_destroy = true   # demo only
  provider      = aws.west   # uses the aliased provider — us-west-2

  tags = { Name = local.archive_bucket_name }
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket   = aws_s3_bucket.archive.id
  provider = aws.west        # must match the bucket's provider
  versioning_configuration { status = "Enabled" }
  depends_on = [aws_s3_bucket.archive]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket   = aws_s3_bucket.archive.id
  provider = aws.west
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
  depends_on = [aws_s3_bucket.archive]
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  provider                = aws.west
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.archive]
}
