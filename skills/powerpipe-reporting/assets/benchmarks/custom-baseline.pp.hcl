# Custom security baseline benchmark.
#
# A small, opinionated benchmark you own — runs alongside the upstream
# CIS/FSBP mods but encodes *your* hard rules (mirrors steering/aws-security.md).
# Each control is one pass/fail query; the benchmark is a tree of controls.
#
# The SQL here intentionally matches the saved queries shipped by the
# `steampipe` skill (queries/security/*.sql) so the two stay in sync — keep
# them identical or have the control `sql` read from a shared query file.
#
# Run a single environment:
#   powerpipe benchmark run acme_aws_reporting.benchmark.custom_baseline \
#     --search-path-prefix aws_prod --output asff > findings-prod.asff.json

benchmark "custom_baseline" {
  title         = "ACME Custom Security Baseline"
  description   = "Hard rules from steering/aws-security.md, enforced as controls."
  children = [
    control.no_public_s3,
    control.no_open_security_groups,
    control.iam_users_have_mfa,
    control.cloudtrail_healthy,
  ]

  tags = {
    type = "Benchmark"
    plugin = "aws"
  }
}

control "no_public_s3" {
  title    = "S3 buckets are not public"
  severity = "critical"
  sql      = <<-EOQ
    select
      arn as resource,
      case when bucket_policy_is_public then 'alarm' else 'ok' end as status,
      case when bucket_policy_is_public
        then name || ' is public via bucket policy'
        else name || ' is not public' end as reason,
      account_id,
      region
    from aws_s3_bucket;
  EOQ
  tags = { service = "S3" }
}

control "no_open_security_groups" {
  title    = "No security group allows 0.0.0.0/0 on non-HTTP(S) ports"
  severity = "high"
  sql      = <<-EOQ
    select
      arn as resource,
      case when cidr_ipv4 = '0.0.0.0/0'
            and not (from_port = 443 and to_port = 443)
        then 'alarm' else 'ok' end as status,
      group_id || ' rule ' || coalesce(from_port::text, 'all') as reason,
      account_id,
      region
    from aws_vpc_security_group_rule
    where type = 'ingress';
  EOQ
  tags = { service = "VPC" }
}

control "iam_users_have_mfa" {
  title    = "IAM console users have MFA enabled"
  severity = "high"
  sql      = <<-EOQ
    select
      arn as resource,
      case when mfa_enabled then 'ok' else 'alarm' end as status,
      name || case when mfa_enabled then ' has MFA' else ' has NO MFA' end as reason,
      account_id
    from aws_iam_user
    where password_enabled;
  EOQ
  tags = { service = "IAM" }
}

control "cloudtrail_healthy" {
  title    = "CloudTrail is multi-region, logging, and validating"
  severity = "medium"
  sql      = <<-EOQ
    select
      arn as resource,
      case when is_multi_region_trail and is_logging and log_file_validation_enabled
        then 'ok' else 'alarm' end as status,
      name || ' multi_region=' || is_multi_region_trail::text
           || ' logging='      || is_logging::text
           || ' validation='   || log_file_validation_enabled::text as reason,
      account_id,
      region
    from aws_cloudtrail_trail;
  EOQ
  tags = { service = "CloudTrail" }
}
