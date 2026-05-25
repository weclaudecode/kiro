# backend.tf
# S3 + DynamoDB remote state. Bootstrap the bucket and lock table once with
# scripts/bootstrap-backend.sh, then reference them here.
#
# If using Terragrunt: delete this file and let Terragrunt's
# `remote_state` / `generate "backend"` block produce backend.tf at apply
# time. Hardcoding the backend in both places leads to drift.

terraform {
  backend "s3" {
    bucket         = "REPLACE-ME-tfstate-bucket"
    key            = "REPLACE-ME/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE-ME-tfstate-locks"
    encrypt        = true

    # Recommended: set kms_key_id to a CMK so state-bucket access can be
    # gated by a key policy in addition to the bucket policy.
    # kms_key_id = "arn:aws:kms:us-east-1:111111111111:key/abcd-..."
  }
}
