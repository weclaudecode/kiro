# Migrating from Raw Terraform

A four-phase migration that keeps the lights on. Do not attempt all four
phases in one PR — each phase is a discrete migration with its own
verification.

## Phase 1 — Introduce the root, leave children unchanged

Create `live/terragrunt.hcl` with the `remote_state` and `generate "provider"`
blocks. For each existing Terraform stack, create a minimal child
`terragrunt.hcl` that includes the root and points `terraform.source` at the
existing in-repo module path. Run `terragrunt init` against an existing
state and verify it picks up the same backend. No change to applied state.

Verification:

- `terragrunt plan` reports zero diff in every migrated stack.
- The state key matches what `path_relative_to_include()` produces; if it
  does not, override `key` in the child or rename the existing state object.

## Phase 2 — Hoist common inputs

Identify variables repeated across every stack (org name, default tags,
common AZ list). Move them into `env.hcl` / `account.hcl` / `region.hcl`
and have the root merge them into `inputs`. Remove the duplicates from each
stack's `terraform.tfvars`.

Verification:

- `terragrunt validate-inputs` reports no missing variables.
- `terragrunt plan` continues to report zero diff per unit.

## Phase 3 — Add dependencies

Replace existing `terraform_remote_state` data sources with `dependency`
blocks. Each conversion is a small, isolated change: one unit at a time,
validate, plan, confirm no diff, commit.

Verification:

- `terragrunt graph-dependencies` matches the implicit graph the team had in
  their heads.
- `run-all plan` from the live root produces a clean run with no manual
  ordering.

## Phase 4 — Convert to remote module sources

Move modules to a separate repo (or just use Git refs into the same repo).
Tag a `v1.0.0`. Switch each child's `terraform.source` from a local path to
a Git URL with `?ref=v1.0.0`. From this point on, module changes go through
the tag-and-bump workflow.

Verification:

- `terragrunt init` downloads modules from Git into the local cache.
- `terragrunt plan` continues to report zero diff after the source swap.

## Module versioning workflow

The piece that gives infra a real change-management story.

1. **Modules live in their own repo.** `terraform-modules` or per-module
   repos. Early-stage projects can keep modules in the live repo under
   `modules/`, but graduate to a separate repo before the modules count
   exceeds a handful.
2. **Tag releases.** Semver tags: `v1.2.0`, `v1.2.1`. Use signed tags if
   the org requires it.
3. **Children pin via `terraform.source`.**
   `source = "git::ssh://git@github.com/acme/terraform-modules.git//vpc?ref=v1.2.0"`.
   The double slash separates the repo from the path within it.
4. **Promotion path.**
   - Make the change in the modules repo on a branch.
   - Test it by pointing one nonprod child at the branch ref:
     `?ref=feature-vpc-flow-logs`.
   - Plan and apply in nonprod, observe.
   - Merge the modules-repo branch and tag `v1.3.0`.
   - Bump nonprod children to `?ref=v1.3.0`, plan, apply.
   - Bump prod children to `?ref=v1.3.0`, plan, apply (per-unit).
5. **Never use a branch ref in production children.** `?ref=main` is silent
   drift — the next apply pulls whatever is on `main` at that moment.

This workflow is what makes Terragrunt worth its complexity. Without
versioned modules, all the DRY benefits collapse: a module change instantly
propagates to every environment on the next apply.
