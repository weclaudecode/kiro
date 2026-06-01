# Mod authoring

A **mod** is a versioned directory of HCL `.pp`/`.pp.hcl` files: `query`,
`control`, `benchmark`, and `dashboard` resources plus a `mod.pp` manifest.
Powerpipe loads every `.pp` file in the mod directory (recursively).

## `mod.pp`

```hcl
mod "acme_aws_reporting" {
  title       = "ACME AWS Multi-Environment Reporting"
  description = "Security posture + cost reporting across AWS environments."

  require {
    mod "github.com/turbot/steampipe-mod-aws-compliance" { version = "1.20.0" }
    mod "github.com/turbot/steampipe-mod-aws-insights"   { version = "1.5.0"  }
  }
}
```

- `powerpipe mod init` scaffolds an empty `mod.pp`.
- `powerpipe mod install` fetches the `require` deps into `.powerpipe/mods/`.
- **Always pin `version`.** Unpinned deps move and your benchmarks shift —
  you get false positives overnight. Bump on purpose, review the diff,
  commit the lockfile.

## Resources and references

Resources are referenced as `<mod>.<type>.<name>` (within the same mod the
mod prefix is optional):

```hcl
query "running_ec2" {
  sql = "select count(*) as value from aws_ec2_instance where instance_state = 'running';"
}

control "iam_users_have_mfa" {
  title    = "IAM console users have MFA"
  severity = "high"
  query    = query.iam_mfa     # reuse a named query …
}

control "inline_example" {
  title = "Inline SQL is fine too"
  sql   = "select arn as resource, 'ok' as status, 'fine' as reason from aws_account;"
}

benchmark "custom_baseline" {
  title    = "ACME Custom Baseline"
  children = [control.iam_users_have_mfa, control.inline_example]
}
```

## Control query contract

A control's SQL must return these columns (extra columns become dimensions):

| Column | Meaning |
|---|---|
| `resource` | The ARN/id being evaluated (one row per resource) |
| `status` | `ok` \| `alarm` \| `skip` \| `info` \| `error` |
| `reason` | Human-readable explanation for this row |
| *(others)* | e.g. `account_id`, `region` — surfaced as dimensions/filters |

## Keep SQL DRY with the steampipe skill

The `steampipe` skill ships saved queries under `queries/`. Prefer having a
control's `sql` be **identical** to the matching saved query (or load it
from a shared file) so the interactive query and the benchmark never drift.

## Params (optional)

Controls/queries can take `param` blocks for reuse across thresholds:

```hcl
query "old_snapshots" {
  param "max_age_days" { default = 90 }
  sql = "select snapshot_id as resource, 'info' as status, age(start_time) as reason from aws_ebs_snapshot where start_time < now() - ($1 || ' days')::interval;"
  args = [param.max_age_days]
}
```
