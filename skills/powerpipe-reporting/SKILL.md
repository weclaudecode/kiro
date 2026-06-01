---
name: powerpipe-reporting
description: Use when building or running Powerpipe dashboards, benchmarks, and custom reports over Steampipe across multiple AWS accounts/environments — covers mod.pp authoring, dashboard/benchmark/control/query HCL, per-environment runs via a Steampipe aggregator, snapshot and HTML/ASFF output, FinOps cost reporting with the AWS Pricing and Cost Explorer MCP servers, and CI integration. Pairs with the steampipe skill (the query/connection layer underneath).
---

# Powerpipe Reporting across AWS Environments

## Overview

Powerpipe is the reporting and visualization layer on top of Steampipe.
Steampipe exposes cloud APIs as Postgres tables; Powerpipe turns SQL
against those tables into **benchmarks** (pass/fail control runs against
CIS/NIST/FSBP and your own controls) and **dashboards** (cards, charts,
tables, inputs) — all defined in HCL inside a versioned **mod** and
distributed as plain text files. A single Steampipe **aggregator**
connection lets one query fan out across every account, so the same mod
produces a per-environment report by changing one `--search-path-prefix`.

This skill is the *authoring + multi-environment reporting + FinOps*
layer. The **query and connection layer lives in the `steampipe`
skill** — read it first for plugin setup, `aws.spc`, the aggregator
pattern, JSONB, and saved queries. This skill assumes those exist and
focuses on: writing mods, parameterizing a report per environment,
producing artifacts (snapshots/HTML/ASFF), and wiring AWS **cost**
reporting via MCP.

Cross-references:
- `steampipe` — connections, aggregator, query patterns, the `cost/`
  saved queries this skill's dashboards build on.
- `terragrunt-multi-account` — the account/environment layout and the
  audit-role the aggregator assumes.
- `aws-solution-architect` — the topology being reported on.
- `gitlab-pipeline` — CI patterns for the publish job.

## When to Use

- Authoring a new Powerpipe **mod** (dashboards + benchmarks + controls).
- Turning ad-hoc `steampipe query` one-offs into a repeatable **report**.
- Running the **same** benchmark/dashboard across dev/staging/prod and
  diffing the results.
- Producing **artifacts** for humans (HTML/snapshot) or pipelines
  (ASFF → Security Hub, JSON → `jq` gate).
- **FinOps**: per-environment cost breakdowns, month-over-month
  comparisons, forecasts, and pre-deploy price estimates — via the AWS
  Pricing and Cost Explorer MCP servers.
- Wiring any of the above into GitLab CI on a schedule.

When NOT to use:
- Writing the underlying SQL or setting up connections → `steampipe`.
- One-off "where is X" questions → just `steampipe query`.
- Real BI / long-term cost data warehousing → Athena/QuickSight/CUR.
- Production app lookups → the SDK, not Steampipe/Powerpipe.

## Mental model: where each piece lives

```
Steampipe (steampipe skill)         Powerpipe (this skill)
─────────────────────────────       ──────────────────────────────
aws.spc + aggregator  ──────────▶   mod.pp (deps + version pins)
SQL queries           ──────────▶   query "..."   {}
                                    control "..." { query = query.x }
                                    benchmark "..."{ children = [...] }
                                    dashboard "..."{ card/chart/table }
                                          │
                              powerpipe server  (interactive, :9033)
                              powerpipe benchmark run (CI artifacts)
                              powerpipe dashboard run (snapshots)

AWS cost (MCP, this skill)
──────────────────────────
aws-pricing-mcp-server     ──▶ unit/list prices (free)   → estimates
cost-explorer-mcp-server   ──▶ actual spend ($0.01/call) → per-env reports
```

## Per-environment reporting — the core pattern

The whole point is *one mod, many environments*. Two layers make that work:

1. **Steampipe aggregator** (defined in the `steampipe` skill's `aws.spc`):
   one connection per account/env (`aws_dev`, `aws_staging`, `aws_prod`)
   plus an `all` aggregator that fans out.
2. **`--search-path-prefix`** at run time selects which environment a
   report targets without editing HCL:

   ```bash
   # same benchmark, three environments, three artifacts
   for env in dev staging prod; do
     powerpipe benchmark run aws_compliance.benchmark.cis_v300 \
       --search-path-prefix "aws_${env}" \
       --output asff > "findings-${env}.asff.json"
   done
   ```

Tag every artifact with the environment and the run date; never let a
prod report overwrite a dev one. See `references/multi-environment.md`.

## Templates

| Template | Purpose |
|---|---|
| `assets/mod.pp` | A starter mod: declares deps on AWS Compliance + AWS Insights, pins versions, sets `require { mod }` |
| `assets/dashboards/account-overview.pp.hcl` | Dashboard: per-env resource + security + cost cards, charts, a findings table, an environment `input` |
| `assets/dashboards/cost-by-environment.pp.hcl` | FinOps dashboard: cost-by-service chart + unattached/idle waste tables fed by the steampipe `cost/` queries |
| `assets/benchmarks/custom-baseline.pp.hcl` | A custom `benchmark` + `control`s (public S3, open SG, IAM MFA, CloudTrail) with severity + tags |
| `assets/.gitlab-ci-powerpipe.yml` | Scheduled CI: install mod (pinned), run benchmark per env via OIDC audit-role, publish HTML + ASFF |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/run-report.sh` | Run a benchmark or dashboard across one/all environments, write timestamped artifacts to `out/<env>/`. Read-only. |
| `scripts/install-mods.sh` | `powerpipe mod install` with pinned versions from `mod.pp`; idempotent. |

## AWS cost reporting via MCP

Two AWS Labs MCP servers (registered in `mcp/mcp.sample.json`) cover the
two cost questions. They are **read-only** and complement Powerpipe's
resource view with real billing data:

| Server | Use it for | Cost | Default in sample |
|---|---|---|---|
| `aws-pricing` (`awslabs.aws-pricing-mcp-server`) | *Estimate before deploy* — unit/list prices, `generate_cost_report` | **Free** | enabled |
| `cost-explorer` (`awslabs.cost-explorer-mcp-server`) | *Actual spend* — `get_cost_and_usage`, `…_comparisons`, `get_cost_forecast`, per-`Environment`-tag breakdown | **$0.01 per Cost Explorer API call** | `disabled: true` — opt in deliberately |

Discipline (see `references/cost-reporting.md` and the
`powerpipe-reporting` steering):
- Cost Explorer bills per call. Pin a date range, group by the
  `Environment` tag, and prefer **monthly** granularity. Don't loop it
  per-account in a wide fan-out without intent.
- Use **pricing** (free) for "what would X cost"; use **cost-explorer**
  (paid) for "what did env Y actually cost last month".
- Never auto-approve Cost Explorer write-equivalent breadth — keep its
  `autoApprove` empty so each billable query prompts.

## References

| Reference | Covers |
|---|---|
| `references/mod-authoring.md` | `mod.pp`, deps, version pinning, `query`/`control`/`benchmark`/`dashboard` blocks, resource refs |
| `references/dashboards.md` | `dashboard` anatomy: `container`, `card`, `chart`, `table`, `input`, `text`, width, `args`, base resources |
| `references/benchmarks.md` | Controls, severity, tags, running benchmarks, output formats, ASFF→Security Hub, JSON gating |
| `references/multi-environment.md` | Aggregator + `--search-path-prefix`, per-env artifacts, diffing runs, naming |
| `references/cost-reporting.md` | The two cost MCP servers: tools, the $0.01 rule, Environment-tag grouping, estimate-vs-actual workflows |
| `references/ci-integration.md` | Scheduled GitLab pipeline, OIDC audit-role, artifact publishing, fail-on-findings |

## Common Mistakes

| Mistake | Why it matters | Fix |
|---|---|---|
| Editing HCL to switch environments | Drift, copy-paste errors, prod/dev mixups | One mod, select env via `--search-path-prefix` |
| Unpinned mod versions | Benchmarks shift overnight, false positives | Pin `version` in `mod.pp`; commit the lockfile |
| `steampipe mod install` | Steampipe mods are deprecated | Use `powerpipe mod install` |
| Looping Cost Explorer per account, daily granularity | Each call is $0.01; this balloons silently | Monthly granularity, group by `Environment` tag, one call |
| Confusing pricing vs cost-explorer | Pricing is estimate (free); CE is actual (paid) | Estimate→pricing, actuals→cost-explorer |
| Artifacts without env/date in the name | prod overwrites dev; can't diff over time | `out/<env>/<benchmark>-<date>.<fmt>` |
| Committing reports with account IDs / findings | Information disclosure if repo leaks | Publish to a private bucket; redact in CI |
| Running the aggregator unfiltered in a demo | One keystroke = 50-account API storm | Default to a single-env search path, opt into `all` |
| `autoApprove` on cost-explorer tools | Silent $0.01 charges per agent turn | Keep CE `autoApprove: []` |

## Quick Reference

```bash
# Install / update mods (pinned)
powerpipe mod install                      # from mod.pp require{} blocks

# Interactive dashboards
powerpipe server                           # http://localhost:9033

# Run a benchmark, pick an environment, emit an artifact
powerpipe benchmark run <mod>.benchmark.<name> \
  --search-path-prefix aws_prod --output asff > findings-prod.asff.json

# Run a dashboard to a shareable snapshot
powerpipe dashboard run <mod>.dashboard.<name> \
  --search-path-prefix aws_dev --output pps > dev.pps

# Output formats: csv | html | json | md | nunit3 | pps (snapshot) | asff
```

| Block | Defines |
|---|---|
| `mod` | The package: name, deps (`require { mod {...} }`), version |
| `query` | A named SQL statement (reusable by controls/dashboards) |
| `control` | One pass/fail check: `query` + `severity` + `tags` |
| `benchmark` | A tree of `children = [control.*, benchmark.*]` |
| `dashboard` | A page of `card`/`chart`/`table`/`input`/`text`/`container` |

| Powerpipe command | Does |
|---|---|
| `powerpipe mod init` | Create `mod.pp` in the current dir |
| `powerpipe mod install` | Fetch declared dependency mods (pinned) |
| `powerpipe server` | Serve dashboards interactively on :9033 |
| `powerpipe benchmark run` | Run a benchmark, emit to stdout in `--output` fmt |
| `powerpipe dashboard run` | Run one dashboard, emit a snapshot/HTML |
