# Repo Layout — the Canonical Pattern

The pattern below is the one most production landing zones converge on. Each
directory level contributes specific variables that flow down via
`read_terragrunt_config` and `find_in_parent_folders`.

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

## What each level contributes

- **`live/terragrunt.hcl` (root).** Backend definition (S3 + DynamoDB),
  provider generation with `assume_role`, common inputs (default tags,
  organisation name). Every child includes this exactly once.
- **`live/<account>/account.hcl`.** Account-scoped facts: `account_id`,
  `account_name`, `account_email`, optionally `sso_url`. Read by the root via
  `find_in_parent_folders("account.hcl")`.
- **`live/<account>/<region>/region.hcl`.** Region-scoped facts: `aws_region`,
  default availability zones, region-specific endpoints.
- **`live/<account>/<region>/<unit>/terragrunt.hcl`.** The unit itself:
  `include "root"`, `terraform.source` pinning a module version, and inputs
  specific to this instance.

The `modules/` directory (or separate modules repo) holds the actual
Terraform module source. Children point at it via `terraform.source`. Once
the team is past initial bootstrap, move modules to their own repo and pin
via Git ref — see `migration.md`.

## DRY hoisting cheat sheet

Choose the right level for each piece of config. Overgeneralisation is more
painful than duplication.

| Where it lives             | What goes there                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| Root `terragrunt.hcl`      | Backend definition, provider generation, `default_tags`, organisation-wide inputs         |
| `env.hcl` (root level)     | Org name, environment label, cross-env defaults that almost never differ                  |
| `account.hcl` (per-account)| `account_id`, `account_name`, account email, SSO URL                                      |
| `region.hcl` (per-region)  | `aws_region`, default AZs, region-specific endpoints                                      |
| `_envcommon/<unit>.hcl`    | Per-stack defaults reused across environments (CIDR sizing, instance families)            |
| Child `terragrunt.hcl`     | Stack-specific inputs (CIDRs, instance sizes, names), `terraform.source`, `dependency`s   |

Anti-patterns to avoid:

- **Hoisting things that legitimately vary.** If `instance_type` differs
  between every unit, hoisting it into `account.hcl` and overriding everywhere
  is worse than leaving it in the child.
- **A single `common_inputs.hcl` with everything.** Sounds DRY, ends up as a
  500-line file no one understands. Keep config close to where it varies.
- **Hardcoded values that should be derived.** `vpc_cidr` per child is fine; a
  hardcoded `account_id` per child is not — that should be
  `local.account_vars.locals.account_id`.
