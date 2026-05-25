# ~/.steampipe/config/aws.spc
#
# Multi-account AWS configuration. Each `connection` block becomes a
# Postgres schema in Steampipe; tables exist inside that schema. The
# `aggregator` connection at the bottom merges all accounts into a single
# logical schema and adds an `account_id` column to every row.
#
# Authentication note: each `profile` value below points at a profile in
# ~/.aws/config. Profiles use SSO or assume-role with `source_profile` —
# never long-lived access keys. The expected layout matches the audit role
# topology in the `terragrunt-multi-account` skill.

# --- Production account ---------------------------------------------------
connection "aws_prod" {
  plugin  = "aws"

  # Matches a profile in ~/.aws/config (SSO or assume-role).
  profile = "aws_prod"

  # Use a pinned region list to avoid scanning every region on broad queries.
  # Use ["*"] only if cross-region inventory is genuinely required.
  regions = ["us-east-1", "us-east-2", "eu-west-1"]

  # Optional: ignore specific error codes that pollute output for resources
  # that are not enabled in this account (e.g. AWSOrganizationsNotInUseException).
  ignore_error_codes = ["AccessDenied", "AccessDeniedException"]
}

# --- Staging account ------------------------------------------------------
connection "aws_stage" {
  plugin  = "aws"
  profile = "aws_stage"
  regions = ["us-east-1", "eu-west-1"]
  ignore_error_codes = ["AccessDenied", "AccessDeniedException"]
}

# --- Development account --------------------------------------------------
connection "aws_dev" {
  plugin  = "aws"
  profile = "aws_dev"
  regions = ["us-east-1", "eu-west-1"]
  ignore_error_codes = ["AccessDenied", "AccessDeniedException"]
}

# --- Aggregator: query all accounts in a single SELECT --------------------
#
# `select * from aws_all.aws_s3_bucket` runs against every connection in
# parallel. Rows include `account_id` so they remain distinguishable.
#
# Wildcards are allowed: `connections = ["aws_*"]` picks up every connection
# whose name starts with `aws_`. Useful when adding new accounts is a single
# block append rather than touching the aggregator list.
connection "aws_all" {
  plugin      = "aws"
  type        = "aggregator"
  connections = ["aws_*"]
}

# --- Adding a new account -------------------------------------------------
#
# 1. Add the assume-role profile to ~/.aws/config:
#
#    [profile aws_audit]
#    source_profile = audit-org
#    role_arn       = arn:aws:iam::444444444444:role/SecurityAudit
#
# 2. Append a new connection block here:
#
#    connection "aws_audit" {
#      plugin  = "aws"
#      profile = "aws_audit"
#      regions = ["us-east-1"]
#    }
#
# 3. Because `aws_all` uses the wildcard `aws_*`, the new account is picked
#    up automatically. Restart Steampipe (`steampipe service restart`) to
#    refresh the schema cache.
