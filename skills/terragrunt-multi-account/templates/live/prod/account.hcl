# live/prod/account.hcl
#
# Account-scoped facts for the prod workload account. Every child unit under
# live/prod/ inherits these values via the root's
# read_terragrunt_config(find_in_parent_folders("account.hcl")) call.
#
# Keep this file small. Only put facts that are genuinely account-wide here
# — anything that varies per region or per stack belongs lower in the tree.

locals {
  account_id    = "111111111111"
  account_name  = "prod"
  account_email = "aws-prod@example.com"

  # Role assumed by the generated AWS provider in every child unit.
  # Created by scripts/bootstrap-account.sh.
  exec_role = "TerraformExecutionRole"

  # Optional: SSO start URL for engineers running terragrunt locally.
  sso_url = "https://acme.awsapps.com/start"

  # Account-wide tag overrides merged with default_tags by the provider.
  account_tags = {
    CostCenter   = "engineering-prod"
    DataClass    = "restricted"
    BackupPolicy = "daily-35d"
  }
}
