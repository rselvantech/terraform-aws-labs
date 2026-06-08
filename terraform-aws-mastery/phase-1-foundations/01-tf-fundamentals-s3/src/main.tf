# Generates a unique 8-character hex suffix — e.g. "a1b2c3d4"
# Generated once on first apply, stored in state, reused on all subsequent applies
resource "random_id" "suffix" {
  byte_length = 4 # 4 bytes = 8 hex characters
}

# ── S3 app bucket ──────────────────────────────────────────────────────────
resource "aws_s3_bucket" "app" {
  bucket        = local.bucket_name # globally unique name from locals.tf
  force_destroy = true              # demo only — allows destroy even if not empty
  # remove this in production

  tags = {
    Name = local.bucket_name # merged with default_tags from provider.tf
  }
}

# ── Versioning ─────────────────────────────────────────────────────────────
# Protects against accidental deletions — every overwrite creates a new version
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket.app] # prevents S3 eventual consistency race condition
}

# ── Server-side encryption ─────────────────────────────────────────────────
# AES256 = AWS-managed keys, always free. Encrypts objects stored on disk.
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # free — no KMS cost
    }
  }

  depends_on = [aws_s3_bucket.app] # prevents S3 eventual consistency race condition
}

# ── Public access block ────────────────────────────────────────────────────
# All four set to true — closes every path to public access
# This is the #1 S3 security control — enable on every bucket
resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true # ignore public ACLs on the bucket
  block_public_policy     = true # reject public bucket policies
  ignore_public_acls      = true # ignore public ACLs on objects
  restrict_public_buckets = true # restrict access to only authorised principals

  depends_on = [aws_s3_bucket.app] # prevents S3 eventual consistency race condition
}
