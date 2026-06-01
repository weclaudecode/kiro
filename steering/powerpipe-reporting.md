<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern:
  - "**/*.pp"
  - "**/*.pp.hcl"
  - "**/mod.pp"
  - "**/.steampipe/**/*.spc"
  - "**/queries/**/*.sql"
---

# Powerpipe / Steampipe Reporting Conventions

Defaults for authoring and running Powerpipe reports over Steampipe across
AWS environments. Deep how-to lives in the `powerpipe-reporting` skill; this
file is the always-apply ruleset when editing mods, dashboards, or queries.

## One mod, many environments
- **Never** edit HCL to switch environments. Select at run time with
  `--search-path-prefix aws_<env>`. The aggregator + per-env connections
  live in Steampipe's `aws.spc` (see the `steampipe` skill).
- Name every artifact `out/<env>/<resource>-<YYYY-MM-DD>.<fmt>`. Env + date,
  always — so prod never overwrites dev and runs are diffable.

## Pin everything
- Pin every `require { mod {...} }` version in `mod.pp`. Unpinned mods drift
  and produce overnight false positives. Bump deliberately, review the diff,
  commit the lockfile.
- Use `powerpipe mod install`, never `steampipe mod install` (deprecated).

## Read-only by default
- Reporting **reads**. Steampipe connections and the CI audit role use
  read-only profiles/roles (SSO or assume-role) — never long-lived keys,
  never write permissions on the accounts being scanned.
- Auth to AWS in CI is OIDC only (`assume-role-with-web-identity`).

## Cost discipline (Cost Explorer bills per call)
- The Cost Explorer MCP server bills **$0.01 per API call**; the Pricing MCP
  server is **free**. Use pricing for estimates, Cost Explorer for actuals.
- Group Cost Explorer by the `Environment` tag; prefer MONTHLY granularity;
  pin date ranges. Don't loop per-account or default to DAILY.
- Keep the cost-explorer server's `autoApprove` empty so every billable call
  prompts. Cache CE results to a file for repeated reads.

## Control query contract
- Control SQL returns `resource`, `status` (`ok|alarm|skip|info|error`),
  `reason`, plus dimensions (`account_id`, `region`). Keep a control's SQL
  identical to the matching saved query in the `steampipe` skill so the
  interactive query and the benchmark never drift.

## Don't leak findings
- Reports contain account IDs and finding detail. Publish to a **private**
  bucket; redact in CI; never commit raw findings to a repo that could go
  public.

## Anti-patterns
- Hardcoding regions/accounts in HCL (read from the connection/search path).
- Running the `all` aggregator unfiltered in a demo (a one-keystroke
  many-account API storm) — default to a single env, opt into `all`.
- Treating Powerpipe output as your bill — it's resource state, not spend.
