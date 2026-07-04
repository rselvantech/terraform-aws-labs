# Resources added in Part B — intentionally empty for now

resource "aws_s3_bucket" "uploads" {
    bucket="cloudnova-legacy-uploads-123458769"
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}