# main.tf
# Minimal example: a single tagged S3 bucket using the post-v4 split pattern.
# A bucket needs every sibling resource below for compliance — see
# references/aws-resources.md for the full pattern.

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.environment}-${var.app}"
}

resource "aws_s3_bucket" "example" {
  bucket = "${local.name_prefix}-example"

  tags = merge(var.tags, {
    Purpose = "example"
  })
}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.example.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket                  = aws_s3_bucket.example.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.example.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}
