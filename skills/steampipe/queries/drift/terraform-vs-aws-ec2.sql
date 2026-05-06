-- Title: Terraform vs AWS EC2 Drift
-- Description: Full-outer-joins the Terraform plugin against the AWS plugin
-- on EC2 instance ID and labels each row as `unmanaged` (in AWS, not in
-- Terraform), `missing` (in Terraform state, not in AWS), or `matched`
-- (present in both — only shown when drift_status='matched' is included
-- in the WHERE clause).
--
-- Requires the Terraform plugin: `steampipe plugin install terraform`.
-- Configure it to point at the project's .tf files or a state file:
--
--   connection "terraform" {
--     plugin = "terraform"
--     paths  = ["/path/to/terraform/**/*.tf"]
--   }
select
    coalesce(t.address, 'aws/' || a.instance_id)         as resource_address,
    t.address                                            as terraform_address,
    t.attributes ->> 'id'                                as terraform_instance_id,
    a.instance_id                                        as aws_instance_id,
    a.account_id,
    a.region,
    a.instance_state,
    a.instance_type,
    a.tags ->> 'Name'                                    as aws_name,
    case
        when t.address     is null then 'unmanaged'
        when a.instance_id is null then 'missing'
        else 'matched'
    end                                                  as drift_status
from
    terraform_resource t
    full outer join aws_ec2_instance a
        on t.attributes ->> 'id' = a.instance_id
where
    t.type = 'aws_instance'
    or a.instance_id is not null
order by
    drift_status,
    a.account_id,
    a.region
