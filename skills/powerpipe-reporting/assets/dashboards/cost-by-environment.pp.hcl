# FinOps dashboard — cost-relevant waste surfaced from resource state.
#
# IMPORTANT: Steampipe/Powerpipe see *resource state*, not your bill. This
# dashboard finds cost *waste* (idle/orphaned resources) from the AWS API.
# For actual dollar spend per environment, use the Cost Explorer MCP server
# (get_cost_and_usage grouped by the `Environment` tag) — see the
# `cost-reporting` reference and `powerpipe-reporting` steering. Cost
# Explorer bills $0.01 per call; this dashboard is free (resource APIs).
#
#   powerpipe dashboard run acme_aws_reporting.dashboard.cost_by_environment \
#     --search-path-prefix aws_prod --output html > prod-cost.html

dashboard "cost_by_environment" {
  title = "Cost & Waste (per environment)"

  text {
    value = "Idle/orphaned resources that cost money for nothing. For billed spend, query Cost Explorer (MCP) grouped by the `Environment` tag."
  }

  container {
    card {
      title = "Unattached EBS volumes"
      width = 4
      type  = "alert"
      sql   = "select count(*) as value from aws_ec2_volume where state = 'available';"
    }
    card {
      title = "Idle Elastic IPs"
      width = 4
      type  = "alert"
      sql   = "select count(*) as value from aws_vpc_eip where association_id is null;"
    }
    card {
      title = "Snapshots > 90 days"
      width = 4
      sql   = <<-EOQ
        select count(*) as value
        from aws_ebs_snapshot
        where start_time < now() - interval '90 days';
      EOQ
    }
  }

  container {
    table {
      title = "Unattached EBS volumes (size = ongoing spend)"
      sql   = <<-EOQ
        select
          volume_id,
          size as gib,
          volume_type,
          region,
          account_id,
          create_time
        from aws_ec2_volume
        where state = 'available'
        order by size desc;
      EOQ
    }

    table {
      title = "Idle Elastic IPs (billed while unassociated)"
      sql   = <<-EOQ
        select
          public_ip,
          region,
          account_id
        from aws_vpc_eip
        where association_id is null;
      EOQ
    }
  }

  container {
    chart {
      title = "EBS GiB allocated by volume type"
      type  = "column"
      sql   = <<-EOQ
        select volume_type, sum(size) as gib
        from aws_ec2_volume
        group by volume_type
        order by gib desc;
      EOQ
    }
  }
}
