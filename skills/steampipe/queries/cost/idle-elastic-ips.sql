-- Title: Idle Elastic IPs
-- Description: Elastic IPs that are not associated with any instance or
-- network interface. AWS bills for unattached EIPs at roughly $3.60 per
-- month each. The estimate column applies the standard rate; adjust if
-- using a different pricing tier.
select
    account_id,
    region,
    allocation_id,
    public_ip,
    domain,
    network_interface_id,
    instance_id,
    association_id,
    3.60                                       as monthly_cost_estimate_usd,
    tags ->> 'Owner'                           as owner,
    tags ->> 'Environment'                     as environment
from
    aws_vpc_eip
where
    association_id is null
    and instance_id   is null
    and network_interface_id is null
order by
    account_id,
    region
