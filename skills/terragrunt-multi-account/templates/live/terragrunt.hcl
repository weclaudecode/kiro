# live/terragrunt.hcl
#
# ROOT Terragrunt config. Every child unit beneath `live/` includes this file
# via `include "root" { path = find_in_parent_folders() }`. It is the single
# source of truth for backend state, the AWS provider, and organisation-wide
# inputs. No resources are declared here.
#
# Hierarchy of variable files walked at parse time:
#   live/env.hcl                         -> org_name, environment label
#   live/<account>/account.hcl           -> account_id, account_name, exec_role
#   live/<account>/<region>/region.hcl   -> aws_region, default AZs
#
# Requires Terragrunt >= 0.60 and Terraform >= 1.6.

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_id    = local.account_vars.locals.account_id
  account_name  = local.account_vars.locals.account_name
  exec_role     = lookup(local.account_vars.locals, "exec_role", "TerraformExecutionRole")
  aws_region    = local.region_vars.locals.aws_region
  org_name      = local.env_vars.locals.org_name
  environment   = local.env_vars.locals.environment

  # State bucket lives in the same account as the workload it manages.
  # Swap this for a central account ID if a single shared bucket is preferred.
  state_bucket  = "${local.org_name}-tfstate-${local.account_id}"
  lock_table    = "${local.org_name}-tflock"
  state_region  = "us-east-1"
  external_id   = lookup(local.env_vars.locals, "external_id", "${local.org_name}-terragrunt")
}

# ---------------------------------------------------------------------------
# Remote state — generates backend.tf in every child unit.
# ---------------------------------------------------------------------------
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = local.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.state_region
    encrypt        = true
    kms_key_id     = "alias/terraform-state"
    dynamodb_table = local.lock_table

    s3_bucket_tags = {
      ManagedBy = "terragrunt"
      Purpose   = "tfstate"
      Account   = local.account_name
    }
    dynamodb_table_tags = {
      ManagedBy = "terragrunt"
      Purpose   = "tflock"
      Account   = local.account_name
    }
  }
}

# ---------------------------------------------------------------------------
# AWS provider — generates provider.tf in every child unit, pinning the
# region and assuming the per-account TerraformExecutionRole.
# ---------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"

  assume_role {
    role_arn     = "arn:aws:iam::${local.account_id}:role/${local.exec_role}"
    session_name = "terragrunt-${local.account_name}"
    external_id  = "${local.external_id}"
  }

  default_tags {
    tags = {
      ManagedBy   = "terragrunt"
      Account     = "${local.account_name}"
      Environment = "${local.environment}"
      Repo        = "${local.org_name}/infra-live"
    }
  }
}
EOF
}

# ---------------------------------------------------------------------------
# Terraform invocation tuning. extra_arguments is appended to every
# terraform CLI call Terragrunt makes in a child unit.
# ---------------------------------------------------------------------------
terraform {
  extra_arguments "common_vars" {
    commands = ["plan", "apply", "destroy", "import", "refresh"]

    optional_var_files = [
      "${get_terragrunt_dir()}/${local.account_name}.tfvars",
      "${get_terragrunt_dir()}/${local.environment}.tfvars",
    ]
  }

  extra_arguments "lock_timeout" {
    commands  = ["apply", "destroy", "import"]
    arguments = ["-lock-timeout=20m"]
  }

  extra_arguments "non_interactive_ci" {
    commands  = ["plan", "apply", "destroy", "import", "init"]
    arguments = ["-input=false"]
  }

  extra_arguments "parallelism" {
    commands  = ["plan", "apply"]
    arguments = ["-parallelism=20"]
  }
}

# ---------------------------------------------------------------------------
# Common inputs flow into every child unit.
# ---------------------------------------------------------------------------
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.env_vars.locals,
  {
    common_tags = {
      ManagedBy   = "terragrunt"
      Account     = local.account_name
      Environment = local.environment
      Org         = local.org_name
    }
  },
)
