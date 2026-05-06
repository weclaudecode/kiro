# live/_envcommon/vpc.hcl
#
# Shared defaults for every VPC unit in the live tree. A child unit pulls
# this in alongside `include "root"`:
#
#   include "envcommon" {
#     path           = "${dirname(find_in_parent_folders())}/_envcommon/vpc.hcl"
#     merge_strategy = "deep"
#     expose         = true
#   }
#
# The child can then override any of the defaults below.

locals {
  # Pulled from the surrounding directory hierarchy so this file is reusable
  # across accounts and regions without parameterisation.
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  azs          = local.region_vars.locals.azs

  # Default subnet pattern: 3 AZs, public + private + intra. CIDR sizing is
  # provided per-child to avoid collisions across environments.
  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  enable_flow_logs       = true
  flow_logs_retention    = 90
}

terraform {
  source = "git::ssh://git@github.com/acme/terraform-modules.git//vpc?ref=v1.4.0"
}

inputs = {
  azs = local.azs

  # Subnets per AZ are derived from the parent CIDR by the module. The child
  # supplies cidr_block and name; everything else has a sensible default.
  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = local.enable_nat_gateway
  one_nat_gateway_per_az = local.one_nat_gateway_per_az
  single_nat_gateway     = false

  enable_flow_log                      = local.enable_flow_logs
  flow_log_destination_type            = "cloud-watch-logs"
  flow_log_cloudwatch_log_group_retention_in_days = local.flow_logs_retention

  tags = {
    Component = "network"
    Tier      = "shared"
    Account   = local.account_name
    Region    = local.aws_region
  }
}
