# CI integration

Run reporting on a schedule, publish artifacts, gate prod on critical
findings. Auth is **OIDC only** (no long-lived AWS keys) — consistent with
`steering/gitlab-ci-conventions.md`. The ready-to-include job is
`assets/.gitlab-ci-powerpipe.yml`; this reference explains the moving parts.

## Shape

1. **Trigger** on a schedule (CI/CD → Schedules), plus a manual run on `main`.
2. **Auth**: exchange the GitLab OIDC token for short-lived creds on a
   read-only **audit role** per environment
   (`assume-role-with-web-identity`).
3. **Setup**: `steampipe service start` (Powerpipe queries through it),
   `powerpipe mod install` (pinned).
4. **Run per environment** via a `parallel: matrix` over `[dev, staging, prod]`,
   each with `--search-path-prefix aws_$ENV`.
5. **Publish**: HTML (humans), ASFF (Security Hub), JSON (the gate) as
   artifacts under `out/<env>/`.
6. **Gate**: fail the prod job if any **critical** control is in `alarm`.

## Why a service + audit role

- Powerpipe queries a running Steampipe service, so start it before the run.
- The audit role is **read-only** (`SecurityAudit` + `ViewOnlyAccess` or a
  scoped policy). The pipeline should never need write/mutate on the targets.
- One role per environment account; the OIDC trust policy restricts to this
  project/ref. See `terragrunt-multi-account` for the role layout.

## Artifacts and retention

- Name `out/<env>/<benchmark>-<date>.<fmt>` — env + date, no collisions.
- `artifacts.expire_in` keeps history bounded; push long-term findings to a
  **private** S3 bucket (don't let account IDs/findings sit in public CI).
- For trend dashboards, import ASFF into Security Hub and let it aggregate,
  rather than diffing artifacts by hand.

## Cost reporting in CI — careful

If you add a Cost Explorer step (the MCP server is for interactive agent
use; in CI call the `ce` API directly or via the agent in headless mode),
remember **every call is $0.01**:

- Run it **monthly**, not per-pipeline, grouped by the `Environment` tag.
- One `get-cost-and-usage` for all environments beats one-per-account.
- Pricing API (estimates) is free — safe to run as often as you like.

## Gating example

```bash
powerpipe benchmark run acme_aws_reporting.benchmark.custom_baseline \
  --search-path-prefix "aws_${ENV}" --output json > b.json
CRIT=$(jq '[.. | objects
            | select(.status?=="alarm" and .severity?=="critical")] | length' b.json)
[ "$CRIT" -eq 0 ] || { echo "critical findings in ${ENV}: $CRIT"; exit 1; }
```

Gate **prod** hard; keep dev/staging report-only so a noisy lower
environment doesn't block delivery.
