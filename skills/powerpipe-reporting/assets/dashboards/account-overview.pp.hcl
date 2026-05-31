# Per-environment account overview dashboard.
#
# Cards (counts) + a chart (resources by service) + a findings table.
# The `environment` input is informational — actual env selection happens
# via `--search-path-prefix aws_<env>` at run time (Steampipe aggregator).
#
#   powerpipe dashboard run acme_aws_reporting.dashboard.account_overview \
#     --search-path-prefix aws_prod --output pps > prod-overview.pps
#   # or browse all dashboards interactively:  powerpipe server

dashboard "account_overview" {
  title = "Account Overview (per environment)"

  text {
    value = "Resource, security, and cost snapshot for the selected environment. Run with `--search-path-prefix aws_<env>` to target dev / staging / prod."
  }

  container {
    card {
      title = "EC2 instances (running)"
      width = 3
      sql   = "select count(*) as value from aws_ec2_instance where instance_state = 'running';"
    }
    card {
      title = "Public S3 buckets"
      width = 3
      type  = "alert"
      sql   = "select count(*) as value from aws_s3_bucket where bucket_policy_is_public;"
    }
    card {
      title = "IAM users without MFA"
      width = 3
      type  = "alert"
      sql   = "select count(*) as value from aws_iam_user where login_profile is not null and not mfa_enabled;"
    }
    card {
      title = "Unattached EBS volumes"
      width = 3
      sql   = "select count(*) as value from aws_ebs_volume where state = 'available';"
    }
  }

  container {
    chart {
      title = "Running EC2 by instance type"
      type  = "column"
      width = 6
      sql   = <<-EOQ
        select instance_type, count(*) as instances
        from aws_ec2_instance
        where instance_state = 'running'
        group by instance_type
        order by instances desc;
      EOQ
    }

    chart {
      title = "Resources by region"
      type  = "donut"
      width = 6
      sql   = <<-EOQ
        select region, count(*) as resources
        from aws_ec2_instance
        group by region
        order by resources desc;
      EOQ
    }
  }

  container {
    table {
      title = "Security findings (custom baseline)"
      sql   = <<-EOQ
        select
          'S3 public' as check, name as resource, account_id, region
        from aws_s3_bucket where bucket_policy_is_public
        union all
        select
          'IAM no MFA', name, account_id, null
        from aws_iam_user where login_profile is not null and not mfa_enabled
        order by check;
      EOQ
    }
  }
}
