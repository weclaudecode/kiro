# Multi-environment reporting

The goal: **one mod, every environment**, with no HCL edits to switch. Two
mechanisms make that work — a Steampipe aggregator and a run-time search path.

## 1. Connections + aggregator (steampipe skill)

In `~/.steampipe/config/aws.spc` (see the `steampipe` skill's `assets/aws.spc`),
one connection per environment plus an `all` aggregator:

```hcl
connection "aws_dev"     { plugin = "aws"  profile = "acme-dev"     regions = ["eu-west-1"] }
connection "aws_staging" { plugin = "aws"  profile = "acme-staging" regions = ["eu-west-1"] }
connection "aws_prod"    { plugin = "aws"  profile = "acme-prod"    regions = ["eu-west-1"] }

connection "aws_all" {
  plugin      = "aws"
  type        = "aggregator"
  connections = ["aws_dev", "aws_staging", "aws_prod"]
}
```

Each profile assumes a **read-only audit role** in that account (the layout
comes from `terragrunt-multi-account`); no long-lived keys.

## 2. Select the environment at run time

`--search-path-prefix` puts a connection first on the Postgres search path,
so unqualified table names (`aws_s3_bucket`) resolve to that environment:

```bash
# one environment
powerpipe benchmark run <mod>.benchmark.custom_baseline \
  --search-path-prefix aws_prod --output asff > findings-prod.asff.json

# every environment, one artifact each
for env in dev staging prod; do
  powerpipe benchmark run <mod>.benchmark.custom_baseline \
    --search-path-prefix "aws_${env}" \
    --output json > "out/${env}/baseline-$(date +%F).json"
done

# all accounts at once (aggregator) — use deliberately, it fans out
powerpipe dashboard run <mod>.dashboard.account_overview \
  --search-path-prefix aws_all --output html > all-accounts.html
```

`scripts/run-report.sh` wraps this (one env or `all`, timestamped output).

## Naming artifacts

Always encode **environment + date** so reports don't collide and you can
diff over time:

```
out/
  dev/baseline-2026-05-31.json
  staging/baseline-2026-05-31.json
  prod/baseline-2026-05-31.json
```

## Diffing runs

Because output is deterministic JSON, compare two days or two environments
with `jq`:

```bash
# what changed in prod between two runs?
diff <(jq -S '.controls' out/prod/baseline-2026-05-30.json) \
     <(jq -S '.controls' out/prod/baseline-2026-05-31.json)

# which alarms exist in prod but not staging?
comm -23 \
  <(jq -r '.. | objects | select(.status=="alarm") | .resource' out/prod/baseline-2026-05-31.json | sort -u) \
  <(jq -r '.. | objects | select(.status=="alarm") | .resource' out/staging/baseline-2026-05-31.json | sort -u)
```

## Cost per environment

Resource APIs show *waste* (idle/orphaned), not dollars. For billed spend
per environment, tag every resource with `Environment` and group Cost
Explorer by that tag — see `cost-reporting.md`.
