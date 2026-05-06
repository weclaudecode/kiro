-- Title: EC2 Instances Grouped by Tag
-- Description: Inventory of running EC2 instances with cost-relevant tags
-- pulled out of the JSONB `tags` map using `->>`. Adjust the WHERE clause
-- to filter by environment, owner, or cost centre.
select
    account_id,
    region,
    instance_id,
    instance_type,
    instance_state,
    private_ip_address,
    public_ip_address,
    tags ->> 'Name'        as name,
    tags ->> 'Environment' as environment,
    tags ->> 'Owner'       as owner,
    tags ->> 'CostCenter'  as cost_center,
    tags ->> 'Application' as application,
    launch_time,
    extract(day from now() - launch_time) as uptime_days
from
    aws_ec2_instance
where
    instance_state = 'running'
order by
    account_id,
    region,
    environment,
    instance_type
