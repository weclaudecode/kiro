# Benchmarks and controls

A **control** is one pass/fail check. A **benchmark** is a tree of controls
(and sub-benchmarks). Use upstream mods (CIS, FSBP, NIST) for breadth and a
small **custom benchmark** for your own hard rules.

## Severity and tags

```hcl
control "no_public_s3" {
  title    = "S3 buckets are not public"
  severity = "critical"            # critical | high | medium | low | none
  sql      = "..."                 # returns resource/status/reason
  tags = {
    service   = "S3"
    framework = "acme-baseline"
  }
}
```

Tags drive grouping/filtering in the dashboard UI and in benchmark output.

## Running a benchmark

```bash
powerpipe benchmark run acme_aws_reporting.benchmark.custom_baseline \
  --search-path-prefix aws_prod \
  --output asff > findings-prod.asff.json
```

### Output formats

| `--output` | Use |
|---|---|
| `html` | Human report (open in a browser / attach to MR) |
| `pps` | Snapshot — re-openable in the Powerpipe UI |
| `asff` | AWS Security Hub Finding Format — import to Security Hub |
| `json` | Programmatic gating with `jq` |
| `csv` / `md` | Spreadsheets / inline docs |
| `nunit3` | CI test-result panels |

## Gating CI on findings

Powerpipe's exit code reflects control results, but for precise gates parse
the JSON. Example: fail only on **critical** alarms.

```bash
powerpipe benchmark run acme_aws_reporting.benchmark.custom_baseline \
  --search-path-prefix aws_prod --output json > b.json

CRIT=$(jq '[.. | objects
            | select(.status? == "alarm" and .severity? == "critical")] | length' b.json)
[ "$CRIT" -eq 0 ] || { echo "critical findings: $CRIT"; exit 1; }
```

## ASFF → Security Hub

`--output asff` emits findings in AWS Security Hub Finding Format. Import
with `aws securityhub batch-import-findings --findings file://findings.asff.json`
(needs `securityhub:BatchImportFindings`). This makes Powerpipe a finding
*source* alongside GuardDuty/Inspector. Keep the import role minimal.

## Per-environment

Run the same benchmark per environment via the aggregator and
`--search-path-prefix`; name artifacts `out/<env>/<benchmark>-<date>.<fmt>`
so prod never overwrites dev and you can diff over time
(`multi-environment.md`).
