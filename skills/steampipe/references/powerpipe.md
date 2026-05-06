# Powerpipe — Benchmarks and Dashboards

Powerpipe replaced Steampipe Mods in 2024. It is now a separate binary that
runs benchmarks against any Steampipe instance.

## Pre-built mods

Pre-built mods cover the major frameworks:

```bash
mkdir aws-compliance && cd aws-compliance
powerpipe mod init
powerpipe mod install github.com/powerpipe/powerpipe-mod-aws-compliance
```

The `aws-compliance` mod ships:

- CIS v1.2 / v1.4 / v1.5 / v3.0
- NIST 800-53 rev5
- AWS Foundational Security Best Practices (FSBP)
- PCI-DSS
- HIPAA
- SOC 2
- FedRAMP

## Run a benchmark

```bash
powerpipe benchmark run aws_compliance.benchmark.cis_v300
powerpipe benchmark run aws_compliance.benchmark.foundational_security
```

## Output formats

Pick by integration target:

```bash
# Human-readable
powerpipe benchmark run aws_compliance.benchmark.cis_v300

# JSON for jq/scripts
powerpipe benchmark run aws_compliance.benchmark.cis_v300 --output json

# CSV for spreadsheets
powerpipe benchmark run aws_compliance.benchmark.cis_v300 --output csv

# AWS Security Hub finding format
powerpipe benchmark run aws_compliance.benchmark.cis_v300 --output asff
```

## Dashboards

`powerpipe server` exposes a web UI on `:9033` with all benchmarks and any
custom dashboards in the mod:

```bash
powerpipe server
# open http://localhost:9033
```

## Writing a custom control

```hcl
control "no_public_buckets" {
  title    = "S3 buckets must not be public"
  severity = "high"
  sql      = <<-EOQ
    select
      arn as resource,
      case
        when bucket_policy_is_public then 'alarm'
        else 'ok'
      end as status,
      name || ' is ' || (
        case when bucket_policy_is_public then 'public' else 'private' end
      ) as reason,
      account_id,
      region
    from aws_s3_bucket;
  EOQ
}
```

Powerpipe controls follow a strict shape: every control SQL must return
`resource`, `status` (`ok`/`alarm`/`info`/`skip`), and `reason`. Optional
columns `account_id`, `region`, and dimensions get used for filtering in
the dashboard UI.

## Group controls into a benchmark

```hcl
benchmark "custom_org_baseline" {
  title    = "Org baseline controls"
  children = [
    control.no_public_buckets,
    control.cloudtrail_multi_region,
    control.iam_users_have_mfa,
  ]
}
```

## Pin mod versions

Pin mod versions in `mod.pp` — never run unpinned mods in CI:

```hcl
mod "local" {
  title = "compliance"
  require {
    mod "github.com/powerpipe/powerpipe-mod-aws-compliance" {
      version = "1.4.0"
    }
  }
}
```

See `templates/custom-control.hcl` for a ready-to-adapt control + benchmark
example.
