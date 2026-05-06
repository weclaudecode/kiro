# `run-all` Safety

`run-all` is the feature that makes Terragrunt feel like a fleet manager. It
is also the feature that, used carelessly, deletes production.

## Commands

- **`terragrunt run-all plan`** — safe and invaluable. Walks the dependency
  graph and runs `terraform plan` in each unit, showing the full picture of
  what would change across the fleet.
- **`terragrunt run-all apply`** — dangerous in production. A single bad
  input in a shared module triggers cascading applies across hundreds of
  units. In prod, default to per-unit `apply` after a clean `run-all plan`.
- **`terragrunt run-all destroy`** — almost never the right answer in prod.
  Use `--terragrunt-include-dir` to scope it to one unit, or run
  `terraform destroy` per unit explicitly.

## Useful flags

- `--terragrunt-include-dir prod/us-east-1/vpc` — restrict `run-all` to a
  single unit and its dependents.
- `--terragrunt-exclude-dir 'prod/**'` — exclude prod from a `run-all`
  covering nonprod.
- `--terragrunt-modules-that-include common.hcl` — operate on units that
  include a specific file (handy for change-detection in CI).
- `--terragrunt-non-interactive` — required in CI; disables prompts.
- `--terragrunt-parallelism 8` — cap concurrent units. The real ceiling is
  AWS provider rate limits (especially IAM and Route 53), not local CPU.
  Start at 4–8 and tune.
- `--terragrunt-ignore-dependency-errors` — keep running other units when
  one fails. Use sparingly and only for analysis runs, never apply.

## Production policy

A reasonable production policy:

- `run-all plan` is allowed everywhere.
- `run-all apply` is allowed only in nonprod.
- Prod applies are per-unit, gated on the human reading the plan.
- `run-all destroy` is never run unattended; if it must be used, scope it
  with `--terragrunt-include-dir` and require a second pair of eyes.

## Partial runs from CI

CI typically wants to plan and apply only the units affected by a merge
request. Two reliable strategies:

1. **Path diff.** `git diff --name-only origin/main...HEAD` and emit one
   `--terragrunt-include-dir` per changed unit. See
   `scripts/detect-changed-units.sh`.
2. **Module-ref diff.** Diff the `?ref=` substrings in `terragrunt.hcl`. Any
   unit whose pinned module changed gets re-planned.

Combine the two for accuracy: a child changes when either its own file
changes or a transitive `_envcommon` include it pulls in changes.

## Concurrency and locks

Concurrent `run-all` invocations against the same backend are not safe even
with the lock table — Terragrunt will fight over module download caches and
state lock acquisitions. CI must serialise per environment using a
`resource_group` (GitLab) or `concurrency` group (GitHub Actions).
