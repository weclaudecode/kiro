# Powerpipe custom control + benchmark template.
#
# Drop this into a Powerpipe mod directory (one created by `powerpipe mod
# init`). Controls return a strict shape: every row must have `resource`,
# `status` ('ok' | 'alarm' | 'info' | 'skip'), and `reason`. The optional
# `account_id` and `region` columns power dimension filters in the
# dashboard UI.

# --- Control: no public S3 buckets ---------------------------------------
#
# Adapt by:
#   * Changing `severity` to match the framework (low | medium | high | critical)
#   * Replacing the SQL with any query that returns the four required columns
#   * Adding `tags` for grouping in the dashboard
control "no_public_buckets" {
  title       = "S3 buckets must not be public"
  description = "Detects buckets that are public via policy or have public-block protections disabled."
  severity    = "high"

  tags = {
    framework = "custom_org_baseline"
    service   = "s3"
  }

  sql = <<-EOQ
    select
      arn as resource,
      case
        when bucket_policy_is_public then 'alarm'
        when block_public_acls    = false then 'alarm'
        when block_public_policy  = false then 'alarm'
        else 'ok'
      end as status,
      name || ' is ' || (
        case
          when bucket_policy_is_public then 'public via policy'
          when block_public_acls    = false then 'missing block_public_acls'
          when block_public_policy  = false then 'missing block_public_policy'
          else 'private'
        end
      ) as reason,
      account_id,
      region
    from aws_s3_bucket;
  EOQ
}

# --- Control: CloudTrail multi-region logging ----------------------------
control "cloudtrail_multi_region" {
  title       = "CloudTrail trails must be multi-region and logging"
  description = "Checks that every account has at least one trail covering all regions and currently logging."
  severity    = "high"

  tags = {
    framework = "custom_org_baseline"
    service   = "cloudtrail"
  }

  sql = <<-EOQ
    select
      coalesce(trail_arn, account_id) as resource,
      case
        when trail_arn is null then 'alarm'
        else 'ok'
      end as status,
      case
        when trail_arn is null
          then 'No multi-region trail with is_logging=true in account ' || account_id
        else 'Multi-region trail ' || trail_name || ' is logging'
      end as reason,
      account_id,
      home_region as region
    from (
      select
        account_id,
        max(arn)         as trail_arn,
        max(name)        as trail_name,
        max(home_region) as home_region
      from aws_cloudtrail_trail
      where is_multi_region_trail = true
        and is_logging            = true
      group by account_id
    ) t
    right join (select distinct account_id from aws_account) a using (account_id);
  EOQ
}

# --- Control: IAM users must have MFA ------------------------------------
control "iam_users_have_mfa" {
  title    = "IAM users with console access must have MFA enabled"
  severity = "critical"

  tags = {
    framework = "custom_org_baseline"
    service   = "iam"
  }

  sql = <<-EOQ
    select
      arn as resource,
      case
        when password_enabled and not mfa_enabled then 'alarm'
        else 'ok'
      end as status,
      name || ' (console=' || password_enabled::text || ', mfa=' || mfa_enabled::text || ')' as reason,
      account_id
    from aws_iam_user;
  EOQ
}

# --- Benchmark: groups the controls into a runnable suite -----------------
#
# Run with:
#   powerpipe benchmark run local.benchmark.custom_org_baseline
#
# Add or remove `control.*` references to expand the benchmark. Nested
# benchmarks are also valid children — useful for organising controls by
# service (network, iam, data, etc.).
benchmark "custom_org_baseline" {
  title       = "Org baseline controls"
  description = "Minimum security controls every account must pass before going to prod."

  children = [
    control.no_public_buckets,
    control.cloudtrail_multi_region,
    control.iam_users_have_mfa,
  ]

  tags = {
    framework = "custom_org_baseline"
  }
}
