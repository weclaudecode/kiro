-- Title: Unattached EBS Volumes Older Than 30 Days
-- Description: Available (unattached) EBS volumes older than 30 days. Sort
-- order surfaces the largest waste first. The `monthly_cost_estimate_usd`
-- column uses gp3 list price ($0.08 per GB-month) as a rough estimate —
-- replace with a real cost lookup for accurate reporting.
select
    account_id,
    region,
    volume_id,
    volume_type,
    size                                  as size_gb,
    iops,
    throughput,
    encrypted,
    create_time,
    extract(day from now() - create_time) as age_days,
    round((size * 0.08)::numeric, 2)      as monthly_cost_estimate_usd,
    tags ->> 'Owner'                      as owner,
    tags ->> 'Environment'                as environment
from
    aws_ec2_volume
where
    state = 'available'
    and create_time < now() - interval '30 days'
order by
    monthly_cost_estimate_usd desc,
    size_gb desc
