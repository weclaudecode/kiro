#!/usr/bin/env bash
#
# bootstrap-account.sh
#
# Idempotently provisions the Terragrunt prerequisites in a target AWS
# account:
#   - S3 bucket for Terraform state (versioned, encrypted, public-blocked)
#   - DynamoDB table for state locking
#   - TerraformExecutionRole IAM role with a trust policy allowing the
#     deployment account's TerraformDeploymentRole to assume it
#
# Usage:
#   ORG_NAME=acme \
#   ACCOUNT_ID=111111111111 \
#   ACCOUNT_NAME=prod \
#   DEPLOYMENT_ACCOUNT_ID=999999999999 \
#   DEPLOYMENT_ROLE_NAME=TerraformDeploymentRole \
#   EXTERNAL_ID=acme-terragrunt \
#   AWS_PROFILE=acme-prod-admin \
#   STATE_REGION=us-east-1 \
#   ./bootstrap-account.sh
#
# AWS_PROFILE must be a profile that already has admin in the target
# account (e.g. SSO into the AWSAdministratorAccess permission set).
# This script is run once per account at landing-zone setup time.

set -euo pipefail

: "${ORG_NAME:?ORG_NAME is required}"
: "${ACCOUNT_ID:?ACCOUNT_ID is required}"
: "${ACCOUNT_NAME:?ACCOUNT_NAME is required}"
: "${DEPLOYMENT_ACCOUNT_ID:?DEPLOYMENT_ACCOUNT_ID is required}"
: "${DEPLOYMENT_ROLE_NAME:=TerraformDeploymentRole}"
: "${EXTERNAL_ID:=${ORG_NAME}-terragrunt}"
: "${AWS_PROFILE:?AWS_PROFILE is required (profile with admin in target account)}"
: "${STATE_REGION:=us-east-1}"
: "${EXEC_ROLE_NAME:=TerraformExecutionRole}"

STATE_BUCKET="${ORG_NAME}-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="${ORG_NAME}-tflock"
KMS_ALIAS="alias/terraform-state"

aws_cmd() {
  AWS_PROFILE="${AWS_PROFILE}" aws --region "${STATE_REGION}" "$@"
}

confirm_account() {
  local actual
  actual=$(aws_cmd sts get-caller-identity --query Account --output text)
  if [[ "${actual}" != "${ACCOUNT_ID}" ]]; then
    echo "ERROR: AWS_PROFILE resolves to account ${actual}, expected ${ACCOUNT_ID}" >&2
    exit 1
  fi
  echo "Confirmed working in account ${ACCOUNT_ID} (${ACCOUNT_NAME})"
}

create_kms_key() {
  if aws_cmd kms describe-key --key-id "${KMS_ALIAS}" >/dev/null 2>&1; then
    echo "KMS alias ${KMS_ALIAS} already exists, skipping"
    return
  fi
  echo "Creating KMS key for state encryption"
  local key_id
  key_id=$(aws_cmd kms create-key \
    --description "Terraform state encryption (${ACCOUNT_NAME})" \
    --tags TagKey=ManagedBy,TagValue=bootstrap-account \
    --query 'KeyMetadata.KeyId' --output text)
  aws_cmd kms create-alias \
    --alias-name "${KMS_ALIAS}" \
    --target-key-id "${key_id}"
  aws_cmd kms enable-key-rotation --key-id "${key_id}"
}

create_state_bucket() {
  if aws_cmd s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    echo "State bucket ${STATE_BUCKET} already exists, skipping create"
  else
    echo "Creating state bucket ${STATE_BUCKET}"
    if [[ "${STATE_REGION}" == "us-east-1" ]]; then
      aws_cmd s3api create-bucket --bucket "${STATE_BUCKET}"
    else
      aws_cmd s3api create-bucket \
        --bucket "${STATE_BUCKET}" \
        --create-bucket-configuration "LocationConstraint=${STATE_REGION}"
    fi
  fi

  aws_cmd s3api put-bucket-versioning \
    --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled

  aws_cmd s3api put-public-access-block \
    --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  aws_cmd s3api put-bucket-encryption \
    --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration "$(cat <<EOF
{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "aws:kms",
      "KMSMasterKeyID": "${KMS_ALIAS}"
    },
    "BucketKeyEnabled": true
  }]
}
EOF
)"

  aws_cmd s3api put-bucket-lifecycle-configuration \
    --bucket "${STATE_BUCKET}" \
    --lifecycle-configuration "$(cat <<'EOF'
{
  "Rules": [{
    "ID": "expire-noncurrent",
    "Status": "Enabled",
    "Filter": {},
    "NoncurrentVersionExpiration": { "NoncurrentDays": 90 },
    "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
  }]
}
EOF
)"

  echo "State bucket ${STATE_BUCKET} configured"
}

create_lock_table() {
  if aws_cmd dynamodb describe-table --table-name "${LOCK_TABLE}" >/dev/null 2>&1; then
    echo "Lock table ${LOCK_TABLE} already exists, skipping"
    return
  fi
  echo "Creating DynamoDB lock table ${LOCK_TABLE}"
  aws_cmd dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --sse-specification Enabled=true \
    --tags Key=ManagedBy,Value=bootstrap-account Key=Purpose,Value=tflock
  aws_cmd dynamodb wait table-exists --table-name "${LOCK_TABLE}"
}

create_exec_role() {
  local trust_policy
  trust_policy=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::${DEPLOYMENT_ACCOUNT_ID}:role/${DEPLOYMENT_ROLE_NAME}"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "${EXTERNAL_ID}" }
    }
  }]
}
EOF
)

  if aws_cmd iam get-role --role-name "${EXEC_ROLE_NAME}" >/dev/null 2>&1; then
    echo "Updating trust policy on ${EXEC_ROLE_NAME}"
    aws_cmd iam update-assume-role-policy \
      --role-name "${EXEC_ROLE_NAME}" \
      --policy-document "${trust_policy}"
  else
    echo "Creating ${EXEC_ROLE_NAME}"
    aws_cmd iam create-role \
      --role-name "${EXEC_ROLE_NAME}" \
      --description "Assumed by Terragrunt to manage resources in ${ACCOUNT_NAME}" \
      --max-session-duration 3600 \
      --tags Key=ManagedBy,Value=bootstrap-account \
      --assume-role-policy-document "${trust_policy}"
  fi

  # Start with AdministratorAccess; tighten once the actual resource set is
  # known. The trust policy is the real boundary: only the deployment role
  # can assume this role, only with the correct external ID.
  aws_cmd iam attach-role-policy \
    --role-name "${EXEC_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
}

main() {
  confirm_account
  create_kms_key
  create_state_bucket
  create_lock_table
  create_exec_role
  echo
  echo "Bootstrap complete for ${ACCOUNT_NAME} (${ACCOUNT_ID})"
  echo "  State bucket : ${STATE_BUCKET}"
  echo "  Lock table   : ${LOCK_TABLE}"
  echo "  Exec role    : arn:aws:iam::${ACCOUNT_ID}:role/${EXEC_ROLE_NAME}"
  echo "  External ID  : ${EXTERNAL_ID}"
}

main "$@"
