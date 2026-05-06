-- Title: EBS Snapshots Older Than 90 Days
-- Description: EBS snapshots older than 90 days, ordered by size. Excludes
-- snapshots owned by AWS marketplace AMIs. Snapshots cost roughly
-- $0.05 per GB-month for standard tier; rate is applied directly to the
-- volume size for a worst-case estimate.
select
    account_id,
    region,
    snapshot_id,
    volume_id,
    volume_size                                            as size_gb,
    state,
    encrypted,
    start_time,
    extract(day from now() - start_time)                   as age_days,
    round((volume_size * 0.05)::numeric, 2)                as monthly_cost_estimate_usd,
    description,
    tags ->> 'Name'                                        as name,
    tags ->> 'BackupPolicy'                                as backup_policy
from
    aws_ebs_snapshot
where
    start_time < now() - interval '90 days'
    and owner_alias is distinct from 'amazon'
order by
    monthly_cost_estimate_usd desc,
    age_days desc
