#!/usr/bin/env bash
# bootstrap-backend.sh
#
# Idempotently provision the S3 bucket and DynamoDB lock table that back
# Terraform remote state. Safe to re-run — every step checks for existing
# resources before acting.
#
# Usage:
#   ./bootstrap-backend.sh
#
# Configuration via environment variables (override before invocation):
#   AWS_REGION              Region for the state bucket and lock table.
#                           Default: us-east-1
#   STATE_BUCKET            Name of the S3 bucket to hold state files.
#                           Required.
#   LOCK_TABLE              DynamoDB table name for state locks.
#                           Default: <STATE_BUCKET>-locks
#   KMS_KEY_ID              Optional CMK ARN or alias for bucket encryption.
#                           Default: aws/s3 (SSE-S3 with AWS-managed key).
#   ACCESS_LOG_BUCKET       Optional pre-existing bucket for S3 server access
#                           logs. If unset, access logging is not configured.
#   ACCESS_LOG_PREFIX       Prefix for access log objects.
#                           Default: tfstate/
#
# Required AWS permissions for the calling principal:
#   s3:CreateBucket, s3:PutBucketVersioning, s3:PutBucketEncryption,
#   s3:PutBucketPublicAccessBlock, s3:PutBucketPolicy, s3:PutBucketLogging,
#   dynamodb:CreateTable, dynamodb:DescribeTable,
#   dynamodb:UpdateContinuousBackups
#
# Example:
#   AWS_REGION=us-east-1 \
#   STATE_BUCKET=acme-tfstate-prod \
#   LOCK_TABLE=acme-tfstate-locks \
#   ./bootstrap-backend.sh

set -euo pipefail

: "${STATE_BUCKET:?STATE_BUCKET must be set (e.g. acme-tfstate-prod)}"
AWS_REGION="${AWS_REGION:-us-east-1}"
LOCK_TABLE="${LOCK_TABLE:-${STATE_BUCKET}-locks}"
KMS_KEY_ID="${KMS_KEY_ID:-}"
ACCESS_LOG_BUCKET="${ACCESS_LOG_BUCKET:-}"
ACCESS_LOG_PREFIX="${ACCESS_LOG_PREFIX:-tfstate/}"

log() { printf '[bootstrap] %s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "missing dependency: $1"; exit 1; }
}

require_cmd aws
require_cmd jq

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
log "account: ${ACCOUNT_ID}  region: ${AWS_REGION}"
log "state bucket: ${STATE_BUCKET}"
log "lock table:  ${LOCK_TABLE}"

#-------------------------------------------------------------------
# S3 state bucket
#-------------------------------------------------------------------
if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  log "bucket ${STATE_BUCKET} already exists; skipping create"
else
  log "creating bucket ${STATE_BUCKET}"
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${AWS_REGION}" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
fi

log "enforcing bucket ownership controls"
aws s3api put-bucket-ownership-controls \
  --bucket "${STATE_BUCKET}" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]' >/dev/null

log "blocking all public access"
aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" >/dev/null

log "enabling versioning"
aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration "Status=Enabled" >/dev/null

log "configuring server-side encryption"
if [ -n "${KMS_KEY_ID}" ]; then
  aws s3api put-bucket-encryption \
    --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration "$(jq -nc \
      --arg kms "${KMS_KEY_ID}" \
      '{Rules:[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:"aws:kms",KMSMasterKeyID:$kms},BucketKeyEnabled:true}]}')" >/dev/null
else
  aws s3api put-bucket-encryption \
    --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration \
      'Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256},BucketKeyEnabled=true}]' >/dev/null
fi

log "applying TLS-only bucket policy"
TLS_POLICY="$(jq -nc \
  --arg bucket_arn "arn:aws:s3:::${STATE_BUCKET}" \
  '{Version:"2012-10-17",Statement:[{Sid:"DenyInsecureTransport",Effect:"Deny",Principal:"*",Action:"s3:*",Resource:[$bucket_arn,($bucket_arn+"/*")],Condition:{Bool:{"aws:SecureTransport":"false"}}}]}')"
aws s3api put-bucket-policy \
  --bucket "${STATE_BUCKET}" \
  --policy "${TLS_POLICY}" >/dev/null

if [ -n "${ACCESS_LOG_BUCKET}" ]; then
  log "enabling access logging to ${ACCESS_LOG_BUCKET}/${ACCESS_LOG_PREFIX}"
  aws s3api put-bucket-logging \
    --bucket "${STATE_BUCKET}" \
    --bucket-logging-status "$(jq -nc \
      --arg target "${ACCESS_LOG_BUCKET}" \
      --arg prefix "${ACCESS_LOG_PREFIX}" \
      '{LoggingEnabled:{TargetBucket:$target,TargetPrefix:$prefix}}')" >/dev/null
else
  log "ACCESS_LOG_BUCKET not set; skipping access logging"
fi

#-------------------------------------------------------------------
# DynamoDB lock table
#-------------------------------------------------------------------
if aws dynamodb describe-table \
    --table-name "${LOCK_TABLE}" \
    --region "${AWS_REGION}" >/dev/null 2>&1; then
  log "lock table ${LOCK_TABLE} already exists; skipping create"
else
  log "creating lock table ${LOCK_TABLE} (PAY_PER_REQUEST)"
  aws dynamodb create-table \
    --region "${AWS_REGION}" \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions "AttributeName=LockID,AttributeType=S" \
    --key-schema "AttributeName=LockID,KeyType=HASH" \
    --billing-mode "PAY_PER_REQUEST" >/dev/null

  log "waiting for lock table to become ACTIVE"
  aws dynamodb wait table-exists \
    --region "${AWS_REGION}" \
    --table-name "${LOCK_TABLE}"
fi

log "enabling point-in-time recovery on lock table"
aws dynamodb update-continuous-backups \
  --region "${AWS_REGION}" \
  --table-name "${LOCK_TABLE}" \
  --point-in-time-recovery-specification "PointInTimeRecoveryEnabled=true" \
  >/dev/null 2>&1 || log "  (PITR may already be enabled; continuing)"

log "done. Use the following backend block:"
cat <<EOF

terraform {
  backend "s3" {
    bucket         = "${STATE_BUCKET}"
    key            = "REPLACE-ME/terraform.tfstate"
    region         = "${AWS_REGION}"
    dynamodb_table = "${LOCK_TABLE}"
    encrypt        = true
$([ -n "${KMS_KEY_ID}" ] && printf '    kms_key_id     = "%s"\n' "${KMS_KEY_ID}")  }
}
EOF
