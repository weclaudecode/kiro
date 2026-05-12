---
name: terragrunt-multi-account
description: Use when orchestrating Terraform across multiple AWS accounts and environments with Terragrunt — covers root vs child terragrunt.hcl, generated backend and provider blocks, includes and unit hierarchies, dependency management, run-all safety, account/environment directory layout, and migration from raw Terraform
---

# Terragrunt for Multi-Account AWS

## Overview

Terragrunt is a thin wrapper around Terraform that solves three concrete
problems at scale: backend duplication, provider duplication, and ordered
execution across many stacks. It earns its keep when an estate has many
environments multiplied by many components — typically a multi-account AWS
landing zone with double-digit stacks.

This skill covers the orchestration layer only. Module design, HCL
primitives, and AWS service selection live in `terraform-aws` and
`aws-solution-architect`.

## When to Use

Use Terragrunt when:

- The estate spans multiple AWS accounts (control tower / landing zone,
  payer + workload split, prod/nonprod separation at the account level).
- There are 10+ Terraform stacks/units sharing backend or provider patterns.
- The same module (VPC, EKS, RDS) is instantiated repeatedly across
  environments and regions.
- There are real dependencies between stacks that need ordering
  (network → compute → workload).
- Module versions need promotion across environments (`v1.2.0` from nonprod
  to prod).

When NOT to use:

- Single-environment repo with one or two stacks — raw Terraform is simpler.
- Team is unfamiliar with Terraform itself — adding Terragrunt doubles the
  surface area to learn.
- Intentionally monolithic stack with no plan to split — DRY benefits never
  materialise.
- A native alternative (Terraform workspaces, Terraform Cloud stacks,
  Spacelift, env0) is already adopted and meets requirements.

## The Model in Five Lines

- Root `terragrunt.hcl` generates `backend.tf` and `provider.tf` for every
  child unit at run time.
- `account.hcl` and `region.hcl` carry account/region vars hoisted via
  `read_terragrunt_config(find_in_parent_folders(...))`.
- Each child unit is `include "root" { path = find_in_parent_folders() }` +
  `terraform { source = "git::...?ref=vX.Y.Z" }` + `inputs = { ... }`.
- Cross-account: the generated provider does
  `assume_role { role_arn = ... }` per account, with the role ARN derived
  from `account.hcl`.
- `dependency` blocks order runs and pass outputs; `mock_outputs` is
  plan-time only — never `apply`.

## Repo Skeleton

The full canonical layout is in `references/repo-layout.md`. Core shape:

```
live/
  terragrunt.hcl                    # ROOT
  env.hcl
  _envcommon/
    vpc.hcl                         # shared per-stack defaults
  prod/
    account.hcl
    us-east-1/
      region.hcl
      vpc/terragrunt.hcl
      eks/terragrunt.hcl            # depends on vpc
  nonprod/
    account.hcl
    us-east-1/
      region.hcl
      ...
```

Working examples for every level live in `assets/live/`.

## Templates

| Path                                                | Purpose                                                           |
| --------------------------------------------------- | ----------------------------------------------------------------- |
| `assets/live/terragrunt.hcl`                     | Root config — `remote_state`, generated provider with assume_role, `default_tags`, `extra_arguments`, common inputs |
| `assets/live/_envcommon/vpc.hcl`                 | Shared VPC defaults included by per-environment children          |
| `assets/live/prod/account.hcl`                   | Account-scoped vars (`account_id`, `account_name`, `exec_role`)   |
| `assets/live/prod/us-east-1/region.hcl`          | Region-scoped vars (`aws_region`, `azs`)                          |
| `assets/live/prod/us-east-1/vpc/terragrunt.hcl`  | Child unit including root + `_envcommon/vpc.hcl`, with overrides  |
| `assets/.gitlab-ci-terragrunt.yml`               | GitLab CI fragment: `validate` / `plan` / `apply` with OIDC and per-environment resource groups |

## Bootstrap

Per-account bootstrap (state bucket, lock table, `TerraformExecutionRole`)
is automated by `scripts/bootstrap-account.sh`. Run once per account at
landing-zone setup time using an SSO admin profile for the target account.

## CI Integration

`assets/.gitlab-ci-terragrunt.yml` shows the full job shape:

- OIDC authentication into `TerraformDeploymentRole` in the deployment
  account.
- Per-environment `TG_DIR` to scope `run-all`.
- `terragrunt:plan` saves plan artifacts; `terragrunt:apply:nonprod` runs
  automatically on the default branch; `terragrunt:apply:prod` is a manual
  per-unit gate behind a `resource_group`.
- `scripts/detect-changed-units.sh` emits `--terragrunt-include-dir` flags
  from a `git diff` against the merge base for partial runs.

For end-to-end pipeline patterns (job templates, OIDC trust, MR-comment
formatting), see the `gitlab-pipeline` skill.

## References

| File                                       | Topic                                                                |
| ------------------------------------------ | -------------------------------------------------------------------- |
| `references/repo-layout.md`                | Canonical multi-account/multi-region directory layout and DRY rules  |
| `references/root-config.md`                | Root `terragrunt.hcl`: backend, generate blocks, common inputs       |
| `references/cross-account-auth.md`         | Generated provider + assume_role chain, OIDC trust policy            |
| `references/dependencies.md`               | `dependency` blocks, mock_outputs, ordering, graph visualisation     |
| `references/run-all-safety.md`             | `run-all` rules, partial runs, parallelism, prod policy              |
| `references/migration.md`                  | Migrating from raw Terraform in four phases; module versioning flow  |

## Common Mistakes

| Mistake                                                                                       | What to do instead                                                                                            |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Hardcoding `account_id` in child `terragrunt.hcl`                                             | Hoist to `account.hcl` and read via `read_terragrunt_config(find_in_parent_folders("account.hcl"))`           |
| `run-all apply` against prod without per-unit gating                                          | Per-unit applies in prod; `run-all apply` only in nonprod after a clean `run-all plan`                        |
| `mock_outputs` reachable from `apply`                                                         | Always set `mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]` — never include `apply`   |
| One giant root `terragrunt.hcl` with every input                                              | Hoist to the right level (env, account, region) — root is for backend/provider only, plus truly global inputs |
| Pinning modules by branch (`?ref=main`) in production                                         | Pin to tags (`?ref=v1.2.0`); use branch refs only on a feature unit during module development                 |
| No `prevent_destroy` on stateful units (RDS, S3 with data, KMS keys)                          | Add `lifecycle { prevent_destroy = true }` in the module; document the unlock-and-destroy procedure           |
| Adopting Terragrunt for a 5-stack repo                                                        | Use raw Terraform; revisit Terragrunt when the count grows or accounts multiply                               |
| Missing DynamoDB lock table → state corruption on concurrent runs                             | Always configure `dynamodb_table` in the `remote_state` block; create the table in `bootstrap-account.sh`     |
| Checking generated `provider.tf` / `backend.tf` into git                                       | `.gitignore` them; let `if_exists = "overwrite_terragrunt"` regenerate every run                              |
| Using `terraform_remote_state` data sources instead of `dependency`                            | Use `dependency` blocks — Terragrunt needs the explicit graph for ordered `run-all`                           |
| Forgetting `--terragrunt-non-interactive` in CI                                               | Add it to every CI invocation; otherwise pipelines hang on prompts                                            |
| Two units writing to the same backend `key`                                                   | The `key = "${path_relative_to_include()}/terraform.tfstate"` pattern prevents this — never hardcode keys     |

## Quick Reference

Common Terragrunt functions:

| Function                                              | One-line use case                                                                  |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `find_in_parent_folders()`                            | Find the root `terragrunt.hcl` for `include "root" { path = ... }`                 |
| `find_in_parent_folders("account.hcl")`               | Walk up the tree to the nearest `account.hcl` (or `env.hcl`, `region.hcl`)         |
| `path_relative_to_include()`                          | Per-unit suffix for the backend `key` — gives every state a unique path            |
| `path_relative_from_include()`                        | The reverse — relative path from the include point back to the unit                |
| `read_terragrunt_config(path)`                        | Load a `.hcl` file (typically `account.hcl`) and access its `locals.*`             |
| `get_aws_account_id()`                                | The account ID of the currently-assumed identity at runtime — useful for sanity checks against `account.hcl` |
| `get_terraform_command()`                             | The terraform command being run (`plan`, `apply`, etc.) — gate behaviour by command |
| `get_env("VAR", "default")`                           | Read an environment variable with a default — for CI-injected values               |
| `run_cmd("--terragrunt-quiet", "git", "rev-parse", "HEAD")` | Run a shell command at parse time — useful for embedding the commit SHA in tags |
| `get_repo_root()`                                     | Absolute path to the repo root — for constructing source paths                     |
| `get_path_to_repo_root()`                             | Relative path from the current unit back to the repo root                          |

Common CLI invocations:

```
terragrunt init                                          # init a single unit
terragrunt plan                                          # plan a single unit
terragrunt apply                                         # apply a single unit (preferred in prod)
terragrunt run-all plan                                  # plan everything below cwd in dependency order
terragrunt run-all apply --terragrunt-non-interactive    # apply fleet (nonprod only)
terragrunt run-all plan --terragrunt-include-dir prod/us-east-1/vpc
terragrunt hclfmt                                        # format all .hcl files in the tree
terragrunt validate-inputs                               # check declared vs supplied inputs
terragrunt graph-dependencies | dot -Tsvg > graph.svg    # visualise the dependency graph
```

This skill assumes Terragrunt 0.60+ (modern `dependency` semantics, current
`generate` behaviour). For Terraform module authoring see `terraform-aws`.
For the surrounding AWS account topology see `aws-solution-architect`. For
the CI pipeline that drives `terragrunt plan` / `apply` see
`gitlab-pipeline`.
