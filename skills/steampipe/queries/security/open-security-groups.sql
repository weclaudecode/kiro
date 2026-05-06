-- Title: Security Groups Open to the Internet
-- Description: Lists ingress rules that allow 0.0.0.0/0 or ::/0 on ports
-- other than 80/443, including the all-protocol wildcard. The per-rule
-- table `aws_vpc_security_group_rule` is preferred over
-- `aws_vpc_security_group` because rule properties are first-class columns
-- (no JSONB unwrapping needed).
select
    account_id,
    region,
    group_id,
    group_name,
    type,
    ip_protocol,
    from_port,
    to_port,
    cidr_ipv4,
    cidr_ipv6,
    description
from
    aws_vpc_security_group_rule
where
    type = 'ingress'
    and (
        cidr_ipv4 = '0.0.0.0/0'
        or cidr_ipv6 = '::/0'
    )
    and (
        ip_protocol = '-1'
        or from_port not in (80, 443)
        or to_port   not in (80, 443)
    )
order by
    account_id,
    region,
    group_id
