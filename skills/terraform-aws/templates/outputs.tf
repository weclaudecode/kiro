# outputs.tf
# Expose the attributes callers will reasonably need (ARNs, IDs, endpoints).
# Mark sensitive outputs explicitly — they still land in state, but Terraform
# redacts them from CLI output and plan logs.

output "bucket_id" {
  description = "Example S3 bucket name."
  value       = aws_s3_bucket.example.id
}

output "bucket_arn" {
  description = "Example S3 bucket ARN, suitable for IAM policies."
  value       = aws_s3_bucket.example.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name for use as a CloudFront origin or VPC endpoint target."
  value       = aws_s3_bucket.example.bucket_regional_domain_name
}

output "account_id" {
  description = "AWS account ID this stack is deployed into."
  value       = data.aws_caller_identity.current.account_id
}

output "db_password" {
  description = "Echo of the configured DB master password. Do not log."
  value       = var.db_password
  sensitive   = true
}
