---
name: terragrunt-multi-account
description: Use when orchestrating Terraform across multiple AWS accounts and environments with Terragrunt — covers root vs child terragrunt.hcl, generated backend and provider blocks, includes and unit hierarchies, dependency management, run-all safety, account/environment directory layout, and migration from raw Terraform
---

# Terragrunt for Multi-Account AWS

This skill is the orchestration layer that sits on top of Terraform. It does not re-cover module design, HCL primitives, resource modelling, or AWS service selection — see the `terraform-aws` and `aws-solution-architect` skills for those. The focus here is what Terragrunt actually adds value for: keeping backend and provider config DRY across many stacks, generating per-unit files at runtime, expressing inter-stack dependencies, and running ordered operations across a fleet of Terraform units.

## 1. Overview

Terragrunt is a thin wrapper around Terraform. It solves three concrete problems that every team running real Terraform at scale eventually hits:

- **Backend config duplication.** Without Terragrunt, every stack repeats an identical `backend "s3"` block with only the `key` differing. Terragrunt generates the backend block per unit from one root file.
- **Provider config duplication.** Cross-account deployments need `assume_role` blocks parameterised by account ID. Terragrunt generates a `provider.tf` per unit with the right role ARN baked in.
- **Ordered execution across many stacks.** Real infra has dependency graphs (VPC before EKS, KMS before S3-with-encryption). Terragrunt models these explicitly with `dependency` blocks and `run-all`.

Use Terragrunt when there are many environments multiplied by many components — typically a multi-account AWS landing zone with double-digit stacks. For a single environment with one or two stacks, raw Terraform is simpler and the wrapper is not worth its learning cost.

## 2. When to Use

Use Terragrunt when:

- The estate spans multiple AWS accounts (control tower / landing zone, payer + workload split, prod/nonprod separation at the account level).
- There are 10+ Terraform stacks/units, especially if they share backend or provider patterns.
- The same module (VPC, EKS, RDS) is instantiated repeatedly across environments and regions.
- There are real dependencies between stacks that need ordering (network → compute → workload).
- A change-management story for module versions across environments is needed (promote `v1.2.0` from nonprod to prod).

Do not use Terragrunt when:

- The repo has a single environment and a single root module. Raw Terraform handles this without the wrapper tax.
- The team is unfamiliar with Terraform itself. Layering Terragrunt on top of shaky Terraform fundamentals doubles the surface area to learn.
- The stack is intentionally monolithic (one root with everything) and there is no plan to split it. The DRY benefits do not materialise.
- A native alternative (Terraform workspaces, Terraform Cloud projects/stacks, Spacelift, env0) is already adopted and meets requirements.

## 3. Repo Layout — the Canonical Pattern

The pattern below is the one most production landing zones converge on. Each directory level contributes specific variables that flow down via `read_terragrunt_config` and `find_in_parent_folders`.

```
live/
  account.hcl                            # NOT used at this level — placeholder; real one lives per-account
  env.hcl                                # cross-env defaults (default region, common tags)
  terragrunt.hcl                         # ROOT — backend, provider generation, common inputs
  mgmt/                                  # management/payer account (Organizations, IAM Identity Center)
    account.hcl                          # account_id, account_name = "mgmt"
    us-east-1/
      region.hcl                         # aws_region = "us-east-1"
      organizations/
        terragrunt.hcl                   # unit: AWS Organizations
      identity-center/
        terragrunt.hcl                   # unit: IAM Identity Center
  log-archive/                           # central logs account
    account.hcl
    us-east-1/
      region.hcl
      logs-bucket/
        terragrunt.hcl
  prod/                                  # workload account: production
    account.hcl                          # account_id = "111111111111"
    us-east-1/
      region.hcl
      vpc/
        terragrunt.hcl
      eks/
        terragrunt.hcl                   # depends on vpc
    eu-west-1/
      region.hcl
      vpc/
        terragrunt.hcl
  nonprod/                               # workload account: nonprod
    account.hcl                          # account_id = "222222222222"
    us-east-1/
      region.hcl
      vpc/
        terragrunt.hcl
      eks/
        terragrunt.hcl
modules/                                 # OR a separate modules repo (preferred long-term)
  vpc/
  eks/
  rds/
```

What each level contributes:

- **`live/terragrunt.hcl` (root).** Backend definition (S3 + DynamoDB), provider generation with `assume_role`, common inputs (default tags, organisation name). Every child includes this exactly once.
- **`live/<account>/account.hcl`.** Account-scoped facts: `account_id`, `account_name`, `account_email`, optionally `sso_url`. Read by the root via `find_in_parent_folders("account.hcl")`.
- **`live/<account>/<region>/region.hcl`.** Region-scoped facts: `aws_region`, default availability zones, region-specific endpoints.
- **`live/<account>/<region>/<unit>/terragrunt.hcl`.** The unit itself: `include "root"`, `terraform.source` pinning a module version, and inputs specific to this instance.

The `modules/` directory (or separate modules repo) holds the actual Terraform module source. Children point at it via `terraform.source`. Once the team is past initial bootstrap, move modules to their own repo and pin via Git ref — see Section 10.

## 4. Root `terragrunt.hcl`

The root is the single place that defines backend and provider behaviour for every unit beneath it. A representative production version:

```hcl
# live/terragrunt.hcl

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_id   = local.account_vars.locals.account_id
  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  org_name     = local.env_vars.locals.org_name
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "${local.org_name}-tfstate-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "alias/terraform-state"
    dynamodb_table = "${local.org_name}-tflock"

    s3_bucket_tags      = { ManagedBy = "terragrunt", Purpose = "tfstate" }
    dynamodb_table_tags = { ManagedBy = "terragrunt", Purpose = "tflock" }
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  assume_role {
    role_arn     = "arn:aws:iam::${local.account_id}:role/TerraformExecutionRole"
    session_name = "terragrunt-${local.account_name}"
  }

  default_tags {
    tags = {
      ManagedBy   = "terragrunt"
      Account     = "${local.account_name}"
      Environment = "${local.env_vars.locals.environment}"
      Repo        = "${local.org_name}/infra-live"
    }
  }
}

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}
EOF
}

inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.env_vars.locals,
)
```

Key points:

- **`path_relative_to_include()`** produces `prod/us-east-1/vpc` for the prod VPC unit, giving every state a unique, predictable key.
- **`generate { ... }` blocks** write `backend.tf` and `provider.tf` into the unit directory at run time. Set `if_exists = "overwrite_terragrunt"` so the generated files are regenerated each run; never check them in.
- **`read_terragrunt_config(find_in_parent_folders("account.hcl"))`** walks up the directory tree to find the nearest `account.hcl`. This is the hoisting mechanism — set a variable once at the right level and let it flow down.
- **State bucket per account.** Either use one central bucket in a dedicated account or a bucket per account. A bucket per account is simpler for permission boundaries; a central bucket is simpler for cross-account search. Pick one and stick with it.
- **`default_tags`** in the provider keeps tags out of every module and applies them automatically to every taggable resource.

A minimal `account.hcl`:

```hcl
# live/prod/account.hcl
locals {
  account_id   = "111111111111"
  account_name = "prod"
  account_email = "aws-prod@example.com"
}
```

A minimal `region.hcl`:

```hcl
# live/prod/us-east-1/region.hcl
locals {
  aws_region = "us-east-1"
}
```

A minimal `env.hcl`:

```hcl
# live/env.hcl
locals {
  org_name    = "acme"
  environment = "prod"  # overridden per-account where needed
}
```

## 5. Child `terragrunt.hcl`

A child unit should be small. The minimum is three blocks: include the root, point at a versioned module, and supply inputs.

```hcl
# live/prod/us-east-1/vpc/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "git::ssh://git@github.com/acme/terraform-modules.git//vpc?ref=v1.2.0"
}

inputs = {
  cidr_block = "10.10.0.0/16"
  azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]
  name       = "prod-use1"
}
```

Notes:

- **`terraform.source` is the unit of versioning.** Each child pins to a specific module ref. Promoting a module change through environments means bumping `?ref=` in nonprod, applying, then bumping it in prod.
- **Local source for development.** While iterating on a module, point at a working copy: `source = "../../../../modules/vpc"`. Switch back to the pinned remote ref before merging.
- **`include "root"`** with no body inherits everything (backend, provider, inputs). Add `expose = true` and use `include.root.locals.foo` if the child needs to read locals from the root.
- **No backend or provider blocks here.** The root generates them. If a child has its own provider needs (different region, alternate role), add a second `generate` block in the child rather than hand-writing one.

## 6. Cross-Account Auth Pattern

The pattern that scales:

1. **One bootstrap role per workload account.** Manually (or via a one-time CloudFormation StackSet) create `TerraformExecutionRole` in every account. Trust policy allows only the deployment account's CI role.
2. **CI authenticates once.** GitLab/GitHub CI uses OIDC to assume `TerraformDeploymentRole` in the deployment account. No long-lived AWS keys.
3. **Generated provider chains the assume.** The root's `generate "provider"` block produces a provider with `assume_role { role_arn = "arn:aws:iam::${account_id}:role/TerraformExecutionRole" }`. The deployment role's identity hops into each target account per unit.
4. **Account ID flows from `account.hcl`.** Never hardcode an account ID in a child unit — always read it via `read_terragrunt_config(find_in_parent_folders("account.hcl"))`.

The trust policy on `TerraformExecutionRole` in a workload account:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::DEPLOYMENT_ACCT:role/TerraformDeploymentRole" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "acme-terragrunt" }
    }
  }]
}
```

If `ExternalId` is in use, add `external_id = "acme-terragrunt"` to the generated `assume_role` block.

For local development, engineers assume `TerraformDeploymentRole` via SSO and run `terragrunt plan` directly — the same chain applies. For details on the deployment-account IAM design, cross-reference the `aws-solution-architect` skill.

## 7. Dependencies Between Stacks

Terragrunt models inter-unit dependencies natively. This is strictly better than `terraform_remote_state` data sources because it gives Terragrunt the dependency graph, enabling correct `run-all` ordering and parallelism.

```hcl
# live/prod/us-east-1/eks/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-0000000000000000a", "subnet-0000000000000000b"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "kms" {
  config_path = "../../kms"
  skip_outputs = false
}

terraform {
  source = "git::ssh://git@github.com/acme/terraform-modules.git//eks?ref=v2.1.0"
}

inputs = {
  cluster_name       = "prod-use1"
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
  kms_key_arn        = dependency.kms.outputs.key_arn
}
```

Rules:

- **`dependency` reads the dep's outputs at plan/apply time.** Terragrunt runs `terraform output` in the dep before processing the dependent unit.
- **`mock_outputs`** lets validate/plan run on a fresh checkout (CI on a feature branch) before the dep exists. Always guard with `mock_outputs_allowed_terraform_commands` to prevent mocks reaching `apply`. Never include `apply` in that list.
- **`skip_outputs = true`** for ordering-only dependencies — the unit must run after the dep but does not consume its outputs (e.g., a CloudTrail unit that needs the logs bucket to exist but reads its name from a separate locals file).
- **Why this is better than `terraform_remote_state` data sources.** The data-source approach hides the graph from Terragrunt, so `run-all` cannot order correctly and engineers must `apply` units manually in the right order. With `dependency`, the graph is explicit and Terragrunt can run in parallel across independent branches.

## 8. `run-all` Safety

`run-all` is the feature that makes Terragrunt feel like a fleet manager. It is also the feature that, used carelessly, deletes production.

- **`terragrunt run-all plan`** — safe and invaluable. Walks the dependency graph and runs `terraform plan` in each unit, showing the full picture of what would change across the fleet.
- **`terragrunt run-all apply`** — dangerous in production. A single bad input in a shared module triggers cascading applies across hundreds of units. In prod, default to per-unit `apply` after a clean `run-all plan`.
- **`terragrunt run-all destroy`** — almost never the right answer in prod. Use `--terragrunt-include-dir` to scope it to one unit, or run `terraform destroy` per unit explicitly.

Useful flags:

- `--terragrunt-include-dir prod/us-east-1/vpc` — restrict `run-all` to a single unit and its dependents.
- `--terragrunt-exclude-dir 'prod/**'` — exclude prod from a `run-all` covering nonprod.
- `--terragrunt-modules-that-include common.hcl` — operate on units that include a specific file (handy for change-detection in CI).
- `--terragrunt-non-interactive` — required in CI; disables prompts.
- `--terragrunt-parallelism 8` — cap concurrent units. The real ceiling is AWS provider rate limits (especially IAM and Route 53), not local CPU. Start at 4–8 and tune.
- `--terragrunt-ignore-dependency-errors` — keep running other units when one fails. Use sparingly and only for analysis runs, never apply.

A reasonable production policy: `run-all plan` is allowed everywhere; `run-all apply` is allowed only in nonprod; prod applies are per-unit, gated on the human reading the plan.

## 9. DRY Patterns — What to Hoist Where

Choose the right level for each piece of config. Overgeneralisation is more painful than duplication.

| Where it lives             | What goes there                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| Root `terragrunt.hcl`      | Backend definition, provider generation, `default_tags`, organisation-wide inputs         |
| `env.hcl` (root level)     | Org name, environment label, cross-env defaults that almost never differ                  |
| `account.hcl` (per-account)| `account_id`, `account_name`, account email, SSO URL                                      |
| `region.hcl` (per-region)  | `aws_region`, default AZs, region-specific endpoints                                      |
| Child `terragrunt.hcl`     | Stack-specific inputs (CIDRs, instance sizes, names), `terraform.source`, `dependency`s   |

Anti-patterns to avoid:

- **Hoisting things that legitimately vary.** If `instance_type` differs between every unit, hoisting it into `account.hcl` and overriding everywhere is worse than leaving it in the child.
- **A single `common_inputs.hcl` with everything.** Sounds DRY, ends up as a 500-line file no one understands. Keep config close to where it varies.
- **Hardcoded values that should be derived.** `vpc_cidr` per child is fine; a hardcoded `account_id` per child is not — that should be `local.account_vars.locals.account_id`.

## 10. Module Versioning Workflow

The piece that gives infra a real change-management story.

1. **Modules live in their own repo.** `terraform-modules` or per-module repos. Early-stage projects can keep modules in the live repo under `modules/`, but graduate to a separate repo before the modules count exceeds a handful.
2. **Tag releases.** Semver tags: `v1.2.0`, `v1.2.1`. Use signed tags if the org requires it.
3. **Children pin via `terraform.source`.** `source = "git::ssh://git@github.com/acme/terraform-modules.git//vpc?ref=v1.2.0"`. The double slash separates the repo from the path within it.
4. **Promotion path.**
   - Make the change in the modules repo on a branch.
   - Test it by pointing one nonprod child at the branch ref: `?ref=feature-vpc-flow-logs`.
   - Plan and apply in nonprod, observe.
   - Merge the modules-repo branch and tag `v1.3.0`.
   - Bump nonprod children to `?ref=v1.3.0`, plan, apply.
   - Bump prod children to `?ref=v1.3.0`, plan, apply (per-unit).
5. **Never use a branch ref in production children.** `?ref=main` is silent drift — the next apply pulls whatever is on `main` at that moment.

This workflow is what makes Terragrunt worth its complexity. Without versioned modules, all the DRY benefits collapse: a module change instantly propagates to every environment on the next apply.

## 11. CI/CD Integration

The rough shape of a Terragrunt CI pipeline:

1. **Authenticate via OIDC.** GitHub Actions or GitLab CI assumes `TerraformDeploymentRole` in the deployment account. No static AWS keys in CI variables.
2. **Detect changed units.** On a merge request, compute the set of units affected by the diff. Two approaches:
   - **Path-based.** Files changed in `prod/us-east-1/vpc/` → run that unit. Crude but cheap.
   - **`--terragrunt-modules-that-include`** to find units that include a changed common file.
   - **Module-ref change detection.** Diff `?ref=` strings — units whose pinned module version changed get re-planned.
3. **Plan job per unit.** `terragrunt plan -out=tfplan -input=false --terragrunt-non-interactive`. Save the plan as a CI artifact and post a summary as an MR comment.
4. **Apply job, gated.** Only on the default branch. Manual click-to-run, never automatic. Apply consumes the saved plan: `terragrunt apply tfplan`.
5. **Per-environment pipeline.** One pipeline per `<account>/<region>` keeps blast radius small and concurrency simple. Fan-out is via `dependency` ordering within a single pipeline run.

For the full pipeline shape (job templates, OIDC trust policy, MR-comment formatting), cross-reference the `gitlab-pipeline` skill — the patterns there apply directly. For the AWS landing zone topology that the pipeline deploys into, see `aws-solution-architect`.

## 12. Common Mistakes

| Mistake                                                                                       | What to do instead                                                                                            |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Hardcoding `account_id` in child `terragrunt.hcl`                                             | Hoist to `account.hcl` and read via `read_terragrunt_config(find_in_parent_folders("account.hcl"))`           |
| `run-all apply` against prod without per-unit gating                                          | Per-unit applies in prod; `run-all apply` only in nonprod after a clean `run-all plan`                        |
| `mock_outputs` reachable from `apply`                                                         | Always set `mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]` — never include `apply`   |
| One giant root `terragrunt.hcl` with every input                                              | Hoist to the right level (env, account, region) — root is for backend/provider only, plus truly global inputs |
| Pinning modules by branch (`?ref=main`) in production                                         | Pin to tags (`?ref=v1.2.0`); use branch refs only on a feature unit during module development                 |
| No `prevent_destroy` on stateful units (RDS, S3 with data, KMS keys)                          | Add `lifecycle { prevent_destroy = true }` in the module; document the unlock-and-destroy procedure           |
| Adopting Terragrunt for a 5-stack repo                                                        | Use raw Terraform; revisit Terragrunt when the count grows or accounts multiply                                |
| Missing DynamoDB lock table → state corruption on concurrent runs                             | Always configure `dynamodb_table` in the `remote_state` block; create the table in a bootstrap unit           |
| Checking generated `provider.tf` / `backend.tf` into git                                       | `.gitignore` them; let `if_exists = "overwrite_terragrunt"` regenerate every run                              |
| Using `terraform_remote_state` data sources instead of `dependency`                            | Use `dependency` blocks — Terragrunt needs the explicit graph for ordered `run-all`                           |
| Forgetting `--terragrunt-non-interactive` in CI                                               | Add it to every CI invocation; otherwise pipelines hang on prompts                                            |
| Two units writing to the same backend `key`                                                   | The `key = "${path_relative_to_include()}/terraform.tfstate"` pattern prevents this — never hardcode keys     |

## 13. Migration from Raw Terraform

A four-phase migration that keeps the lights on:

**Phase 1 — Introduce the root, leave children unchanged.** Create `live/terragrunt.hcl` with the `remote_state` and `generate "provider"` blocks. For each existing Terraform stack, create a minimal child `terragrunt.hcl` that includes the root and points `terraform.source` at the existing in-repo module path. Run `terragrunt init` against an existing state and verify it picks up the same backend. No change to applied state.

**Phase 2 — Hoist common inputs.** Identify variables repeated across every stack (org name, default tags, common AZ list). Move them into `env.hcl` / `account.hcl` / `region.hcl` and have the root merge them into `inputs`. Remove the duplicates from each stack's `terraform.tfvars`.

**Phase 3 — Add dependencies.** Replace existing `terraform_remote_state` data sources with `dependency` blocks. Each conversion is a small, isolated change: one unit at a time, validate, plan, confirm no diff, commit.

**Phase 4 — Convert to remote module sources.** Move modules to a separate repo (or just use Git refs into the same repo). Tag a `v1.0.0`. Switch each child's `terraform.source` from a local path to a Git URL with `?ref=v1.0.0`. From this point on, module changes go through the tag-and-bump workflow.

Do not attempt all four phases in one PR. Each phase is a discrete migration with its own verification.

## 14. Quick Reference

Common Terragrunt functions and where they earn their keep:

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
terragrunt init                                      # init a single unit
terragrunt plan                                      # plan a single unit
terragrunt apply                                     # apply a single unit (preferred in prod)
terragrunt run-all plan                              # plan everything below cwd in dependency order
terragrunt run-all apply --terragrunt-non-interactive    # apply fleet (nonprod only)
terragrunt run-all plan --terragrunt-include-dir prod/us-east-1/vpc
terragrunt hclfmt                                    # format all .hcl files in the tree
terragrunt validate-inputs                           # check declared vs supplied inputs
terragrunt graph-dependencies | dot -Tsvg > graph.svg    # visualise the dependency graph
```

Cross-reference: this skill assumes Terragrunt 0.60+ (modern `dependency` semantics, current `generate` behaviour). For Terraform module authoring see `terraform-aws`. For the surrounding AWS account topology see `aws-solution-architect`. For the CI pipeline that drives `terragrunt plan` / `apply` see `gitlab-pipeline`.
