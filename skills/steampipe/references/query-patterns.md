# Query Patterns

These run unmodified against a default `aws` plugin install (replace `aws`
with `aws_all` if using an aggregator).

## Public S3 buckets across all accounts

```sql
select account_id, name, region
from aws_s3_bucket
where bucket_policy_is_public
   or block_public_acls = false
   or block_public_policy = false;
```

## Security groups open to 0.0.0.0/0 on non-HTTP ports

```sql
select account_id, region, group_id, group_name,
       from_port, to_port, ip_protocol
from aws_vpc_security_group_rule
where cidr_ipv4 = '0.0.0.0/0'
  and type = 'ingress'
  and (from_port not in (80, 443) or ip_protocol = '-1');
```

## IAM users with passwords but no MFA

```sql
select account_id, name, create_date, password_last_used
from aws_iam_user
where mfa_enabled = false
  and password_enabled = true;
```

## Stale IAM access keys (>90 days)

```sql
select u.account_id, u.name as user_name,
       k.access_key_id, k.create_date,
       extract(day from now() - k.create_date) as age_days
from aws_iam_user u,
     jsonb_array_elements(u.access_keys) as k_obj,
     aws_iam_access_key k
where k.user_name = u.name
  and k.account_id = u.account_id
  and k.create_date < now() - interval '90 days'
  and k.status = 'Active';
```

## EC2 instances by tag, with cost-relevant fields

```sql
select account_id, region, instance_id, instance_type,
       tags ->> 'Owner' as owner,
       tags ->> 'CostCenter' as cost_center,
       launch_time
from aws_ec2_instance
where instance_state = 'running'
  and tags ->> 'Environment' = 'prod';
```

## Unattached EBS volumes (cost waste)

```sql
select account_id, region, volume_id, size, volume_type,
       create_time,
       extract(day from now() - create_time) as age_days
from aws_ec2_volume
where state = 'available'
  and create_time < now() - interval '30 days'
order by size desc;
```

## JSONB unwrapping — IAM policies that allow `*` on `*`

```sql
select account_id, name,
       statement ->> 'Effect'   as effect,
       statement -> 'Action'    as actions,
       statement -> 'Resource'  as resources
from aws_iam_policy,
     jsonb_array_elements(policy_std -> 'Statement') as statement
where statement ->> 'Effect' = 'Allow'
  and statement -> 'Resource' @> '"*"'
  and statement -> 'Action'   @> '"*"';
```

The `@>` operator tests JSONB containment. `->` returns JSONB, `->>` returns
text. `?` tests for key existence.

## CloudTrail trails not logging to all regions

```sql
select account_id, name, home_region,
       is_multi_region_trail, is_logging
from aws_cloudtrail_trail
where is_multi_region_trail = false
   or is_logging = false;
```

## Drift detection — Terraform plugin against AWS plugin

```sql
select t.address,
       t.attributes ->> 'id' as tf_id,
       a.instance_id          as aws_id,
       case
         when t.address is null     then 'unmanaged'
         when a.instance_id is null then 'missing'
         else 'matched'
       end as drift_status
from terraform_resource t
full outer join aws_ec2_instance a
  on t.attributes ->> 'id' = a.instance_id
where t.type = 'aws_instance'
  and (t.address is null or a.instance_id is null);
```

This requires the Terraform plugin pointed at a state file or a directory
of `.tf` files.

## Cross-cloud query

GitHub repos without branch protection, joined to AWS resources tagged with
the repo name:

```sql
with unprotected_repos as (
  select name as repo_name, default_branch
  from github_my_repository
  where default_branch_protection_rule is null
)
select r.repo_name,
       i.account_id,
       i.region,
       i.instance_id,
       i.tags ->> 'Repo' as repo_tag
from unprotected_repos r
join aws_ec2_instance  i
  on i.tags ->> 'Repo' = r.repo_name
where i.instance_state = 'running';
```

Same pattern works for Kubernetes (`kubernetes_pod`), Azure
(`azure_storage_account`), GCP (`gcp_compute_instance`), and dozens of
SaaS plugins (Datadog, Okta, Snowflake, Stripe).

## JSONB operator reference

| Operator | Returns | Use |
|---|---|---|
| `->` | JSONB | Navigate nested object/array |
| `->>` | text | Extract scalar as text |
| `@>` | bool | Containment test |
| `<@` | bool | Reverse containment |
| `?` | bool | Key exists at top level |
| `?\|` | bool | Any of these keys exists |
| `?&` | bool | All of these keys exist |
| `jsonb_array_elements()` | setof JSONB | Unnest JSON array into rows |
| `jsonb_each()` | setof key/value | Unnest JSON object |

## Export to S3-friendly CSV

```bash
steampipe query --output csv \
  "select account_id, name, region from aws_s3_bucket" \
  > /tmp/buckets.csv
aws s3 cp /tmp/buckets.csv s3://audit-snapshots/$(date +%F)/buckets.csv
```
