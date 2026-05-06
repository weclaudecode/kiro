# Root `terragrunt.hcl`

The root is the single place that defines backend and provider behaviour for
every unit beneath it. A representative production version lives at
`templates/live/terragrunt.hcl`; the structure is described below.

## Structure

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
EOF
}

inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.env_vars.locals,
)
```

## Key points

- **`path_relative_to_include()`** produces `prod/us-east-1/vpc` for the prod
  VPC unit, giving every state a unique, predictable key.
- **`generate { ... }` blocks** write `backend.tf` and `provider.tf` into the
  unit directory at run time. Set `if_exists = "overwrite_terragrunt"` so the
  generated files are regenerated each run; never check them in.
- **`read_terragrunt_config(find_in_parent_folders("account.hcl"))`** walks up
  the directory tree to find the nearest `account.hcl`. This is the hoisting
  mechanism — set a variable once at the right level and let it flow down.
- **State bucket per account.** Either use one central bucket in a dedicated
  account or a bucket per account. A bucket per account is simpler for
  permission boundaries; a central bucket is simpler for cross-account
  search. Pick one and stick with it.
- **`default_tags`** in the provider keeps tags out of every module and
  applies them automatically to every taggable resource.
- **`terraform.extra_arguments`** is the right place for `-lock-timeout`, for
  loading well-known `*.tfvars` files, and for forcing `-input=false` in CI.
  See `templates/live/terragrunt.hcl` for the full block.

## Minimal supporting files

`live/env.hcl`:

```hcl
locals {
  org_name    = "acme"
  environment = "prod"  # overridden per-account where needed
}
```

`live/prod/account.hcl`:

```hcl
locals {
  account_id    = "111111111111"
  account_name  = "prod"
  account_email = "aws-prod@example.com"
  exec_role     = "TerraformExecutionRole"
}
```

`live/prod/us-east-1/region.hcl`:

```hcl
locals {
  aws_region = "us-east-1"
  azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

## Child unit shape

A child unit should be small. The minimum is three blocks: include the root,
point at a versioned module, and supply inputs.

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

- **`terraform.source` is the unit of versioning.** Each child pins to a
  specific module ref. Promoting a module change through environments means
  bumping `?ref=` in nonprod, applying, then bumping it in prod.
- **Local source for development.** While iterating on a module, point at a
  working copy: `source = "../../../../modules/vpc"`. Switch back to the
  pinned remote ref before merging.
- **`include "root"`** with no body inherits everything (backend, provider,
  inputs). Add `expose = true` and use `include.root.locals.foo` if the child
  needs to read locals from the root.
- **No backend or provider blocks here.** The root generates them. If a child
  has its own provider needs (different region, alternate role), add a second
  `generate` block in the child rather than hand-writing one.
- **Shared per-stack defaults** belong in `_envcommon/<unit>.hcl` and are
  pulled in with a second `include` block. See
  `templates/live/_envcommon/vpc.hcl`.
