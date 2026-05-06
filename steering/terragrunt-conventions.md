<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern: "**/terragrunt.hcl"
---

# Terragrunt Conventions

## Repo layout (multi-account)

```
live/
  _envcommon/                shared module-level config blocks
  account.hcl                per-account vars (account_id, account_name)
  region.hcl                 per-region vars
  env.hcl                    per-env vars (env_name, env_short)
  <account>/
    <region>/
      <env>/
        <component>/
          terragrunt.hcl     thin wrapper: include + inputs
modules/                     in-repo terraform modules (or pinned source)
```

Components are small (one logical concern: `vpc`, `rds`, `lambda-ingest`).
Avoid mega-components.

## `terragrunt.hcl` shape

A leaf `terragrunt.hcl` should be ~20 lines: `include` blocks, a `terraform
{ source = "..." }`, and an `inputs = { ... }`. No resources, no logic.
Logic belongs in `_envcommon` or in the module.

## Backend
- One `remote_state` block in the root `terragrunt.hcl`. Generates the S3
  backend per component using the component path as the state key.
- DynamoDB lock table per AWS account, not per environment.

## Sources
- `terraform { source = "git::ssh://git@gitlab.example.com/infra/modules.git//<module>?ref=v1.4.0" }`
  — pin to a tag, never `main`.
- For in-repo modules during dev: `source = "${get_parent_terragrunt_dir()}/../modules/<m>"`,
  but pin to a tag before merging.

## Account isolation
- Each AWS account has its own AWS profile + its own backend bucket in that
  same account. No cross-account state writes.
- The pipeline assumes a role *into* the target account using OIDC; it does
  not read state from a different account.

## Don't
- Put `for_each` in `terragrunt.hcl` to fan out environments. Make the env
  explicit on disk — easier to diff, easier to plan in isolation.
- Use `read_terragrunt_config` to reach across the tree more than one hop.
  If you need a value three levels away, lift it.
- Mix `terragrunt apply-all` with environments that have human approval
  gates. Apply leaf-by-leaf in CI.
