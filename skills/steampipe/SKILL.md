---
name: steampipe
description: Use when querying cloud APIs with SQL for inventory, audit, compliance, or cost analysis — covers Steampipe plugin setup, multi-account/multi-region AWS connections via aggregators, query patterns, Powerpipe benchmarks (CIS, NIST, AWS Foundational Security), Flowpipe pipelines, JSONB column patterns, and CI integration
---

# Steampipe for Cloud Querying

## Overview

Steampipe turns cloud APIs into Postgres tables. An embedded PostgreSQL
serves SQL queries that translate into live API calls through per-cloud
foreign-data-wrapper plugins. Every cloud resource is a row, every nested
attribute is a JSONB field, and a single aggregator connection can query
hundreds of accounts in parallel. Powerpipe sits on top for benchmarks
and dashboards (CIS, NIST, AWS FSBP, PCI, HIPAA); Flowpipe glues query
results into HTTP-driven workflows.

Cross-references: `terragrunt-multi-account` for the audit role layout
the aggregator assumes, `aws-solution-architect` for the topology being
audited, `security-code-reviewer` for how findings feed into review,
`gitlab-pipeline` for the CI integration.

## When to Use

- Security audit across many AWS accounts ("any IAM users without MFA?")
- Asset inventory ("every running EC2 in eu-west-1 tagged Environment=prod")
- Drift detection — Terraform plugin joined against the cloud plugin
- Ad-hoc "where is X" questions during incident response
- Compliance benchmarks (CIS, NIST 800-53, AWS FSBP, PCI-DSS, HIPAA)
- Cost anomaly hunting ("EBS volumes attached to nothing for >30 days")
- Cross-cloud joins (GitHub repo metadata vs. AWS resources tagged with the repo)

When NOT to use:

- High-frequency production lookups — every query hits the upstream API and is rate-limited
- Real data warehousing — use Athena, Snowflake, or Redshift
- Long-running ETL — Steampipe caches in-memory and is not designed for hour-long jobs
- Anything where stale data is unacceptable — even with cache disabled, AWS API consistency varies

## Setup in 5 Lines

1. **Install:** `brew install turbot/tap/steampipe` (macOS), the `steampipe.sh`
   installer on Debian/Ubuntu, or `turbot/steampipe` Docker image for CI.
2. **Plugin:** `steampipe plugin install aws` (and `terraform`, `github`,
   `kubernetes`, etc. as needed).
3. **Configure connections** in `~/.steampipe/config/aws.spc` — see
   `templates/aws.spc` for a multi-account starter.
4. **Aggregator:** define a `type = "aggregator"` connection that fans out
   across `aws_*` profiles so one SELECT hits every account.
5. **Run:** `steampipe query` for the interactive REPL, or
   `steampipe service start` for a real Postgres endpoint on port 9193.

## Templates

| Template | Purpose |
|---|---|
| `templates/aws.spc` | Multi-account `aws.spc` with three named connections plus an aggregator and inline comments for adding new accounts |
| `templates/custom-control.hcl` | Powerpipe control + benchmark template (public-S3, CloudTrail, IAM-MFA) |
| `templates/.gitlab-ci-steampipe.yml` | GitLab CI job using `turbot/steampipe:latest`, OIDC into an audit role, ASFF benchmark output, `jq`-based fail-on-findings |

## Saved Queries

| File | Description |
|---|---|
| `queries/security/public-s3-buckets.sql` | Buckets public via policy or with public-block protections off |
| `queries/security/open-security-groups.sql` | Ingress rules allowing 0.0.0.0/0 or ::/0 on non-HTTP ports |
| `queries/security/iam-users-without-mfa.sql` | Console users with `mfa_enabled = false` |
| `queries/security/iam-policies-with-resource-star.sql` | `Allow` statements with `Action=*` on `Resource=*` (uses `policy_std`) |
| `queries/security/cloudtrail-disabled.sql` | Trails not multi-region, not logging, no validation, or unencrypted |
| `queries/inventory/ec2-by-tag.sql` | Running EC2 inventory pulling cost-relevant tags out of JSONB |
| `queries/inventory/rds-public.sql` | RDS instances with `publicly_accessible = true` |
| `queries/inventory/lambda-functions-summary.sql` | Per-function runtime, memory, role, last-deploy age |
| `queries/cost/ebs-unattached.sql` | Available EBS volumes older than 30 days |
| `queries/cost/idle-elastic-ips.sql` | EIPs with no association, no instance, no ENI |
| `queries/cost/old-snapshots.sql` | EBS snapshots older than 90 days, sorted by size |
| `queries/drift/terraform-vs-aws-ec2.sql` | Full-outer-join Terraform plugin against AWS plugin (requires `steampipe plugin install terraform`) |

## References

| Reference | Covers |
|---|---|
| `references/install-and-architecture.md` | Plugins, three execution modes, service mode, table conventions |
| `references/aws-connections.md` | Per-account and aggregator config, SSO and assume-role auth |
| `references/query-patterns.md` | Core SQL patterns and JSONB usage with runnable examples |
| `references/powerpipe.md` | Benchmarks, controls, dashboards, mod pinning |
| `references/flowpipe.md` | Short workflow-automation reference |
| `references/performance-and-caching.md` | Rate limits, partition pushdown, `search_path`, cache control |

## Common Mistakes

| Mistake | Why it matters | Fix |
|---|---|---|
| Long-lived AWS keys in `aws.spc` | Keys end up in git, no rotation | Use SSO or assume-role profiles in `~/.aws/config` |
| `regions = ["*"]` for every query | Slow, high API quota, multi-minute scans | Pin regions per connection or `where region = 'us-east-1'` |
| No aggregator, hand-unioning per-account queries | Brittle, breaks when accounts added/removed | Define a single aggregator connection |
| JSONB with dot syntax | Postgres uses `->`/`->>`, not `.` | `tags ->> 'Owner'`, not `tags.Owner` |
| Stale results from cache | Default 5-min cache surprises during audits | `set cache = false` or `--cache=false` |
| `select * from aws_ec2_instance` across 50 accounts | Hammers EC2 DescribeInstances, may throttle prod | Project specific columns, filter on partition keys |
| Steampipe for production app lookups | Every call hits AWS, cache lies, scaling tops out | Use boto3 / SDK directly with proper error handling |
| Confusing Steampipe Mods with Powerpipe Mods | Steampipe Mods are deprecated; tutorials still reference them | Use `powerpipe mod install`, not `steampipe mod install` |
| Unpinned Powerpipe mod versions in CI | Benchmarks shift under you, false positives appear overnight | Pin `version = "x.y.z"` in `mod.pp` |
| Committing query results with account IDs | Information disclosure if repo goes public | Redact in CI step or store findings in a private S3 bucket |
| Running aggregator in interactive without filters | Single-keystroke 50-account scan during a demo | Default to a single-account `search_path`, opt into aggregator explicitly |
| Forgetting that JSONB `?` is key-existence | `where tags ? 'Owner'` is correct | Know the JSONB operator family |

## Quick Reference

Common AWS tables:

| Table | Description |
|---|---|
| `aws_iam_user` | IAM users with MFA status, console access, attached policies |
| `aws_iam_role` | IAM roles, trust policies, attached managed/inline policies |
| `aws_iam_policy` | Managed policies with `policy_std` for normalized navigation |
| `aws_iam_access_key` | Access keys with status, last-used, age |
| `aws_s3_bucket` | Buckets with public-access settings, encryption, versioning |
| `aws_ec2_instance` | EC2 instances with state, tags, network interfaces |
| `aws_ec2_volume` | EBS volumes including unattached/orphaned |
| `aws_vpc_security_group_rule` | Per-rule view of SG ingress/egress (better than `aws_vpc_security_group`) |
| `aws_cloudtrail_trail` | Trails with multi-region, logging status, log file validation |
| `aws_kms_key` | KMS keys with rotation status, key policy |
| `aws_lambda_function` | Lambda functions with runtime, role, env vars |
| `aws_rds_db_instance` | RDS instances with public-access, encryption, backup config |
| `aws_guardduty_finding` | GuardDuty findings if enabled |
| `aws_securityhub_finding` | Security Hub aggregated findings |

JSONB operators:

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

Output flags:

| Flag | Format |
|---|---|
| `--output json` | Array of row objects, ideal for `jq` |
| `--output csv` | CSV with headers, for spreadsheets / `\copy` |
| `--output table` | Default human-readable |
| `--output line` | One field per line per row, for grep |
| `--output asff` | AWS Security Hub Finding Format (Powerpipe only) |

Cache controls:

| Mechanism | Effect |
|---|---|
| `set cache = false` | Disable for current REPL session |
| `set cache_ttl = 60` | Lower TTL to 60 seconds |
| `--cache=false` | Per-query disable on the CLI |
| `STEAMPIPE_CACHE=false` | Env var, disables across all invocations |
| `cache_ttl` in `default.spc` | Persistent global default |
