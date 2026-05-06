# outputs.tf
# Expose the attributes callers will reasonably need. Internal IDs (the
# bucket policy, the lifecycle rule) are not exposed — that is implementation
# detail.

output "id" {
  description = "Bucket name (also the bucket ID)."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN, suitable for use in IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Bucket domain name (DNS)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional bucket domain name, for CloudFront origins or VPC endpoints."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
