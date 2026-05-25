# live/prod/us-east-1/vpc/terragrunt.hcl
#
# Production VPC in us-east-1. Inherits everything from the root and from
# _envcommon/vpc.hcl; only the per-environment specifics are declared here.

include "root" {
  path = find_in_parent_folders()
}

include "envcommon" {
  path           = "${dirname(find_in_parent_folders())}/_envcommon/vpc.hcl"
  merge_strategy = "deep"
  expose         = true
}

# Pin a specific module version in this child. Uncomment to override the
# default declared in _envcommon/vpc.hcl while testing a new release.
# terraform {
#   source = "git::ssh://git@github.com/acme/terraform-modules.git//vpc?ref=v1.4.1"
# }

inputs = {
  name       = "prod-use1"
  cidr_block = "10.10.0.0/16"

  # Three /20s per tier across three AZs.
  public_subnets  = ["10.10.0.0/20",  "10.10.16.0/20", "10.10.32.0/20"]
  private_subnets = ["10.10.64.0/20", "10.10.80.0/20", "10.10.96.0/20"]
  intra_subnets   = ["10.10.144.0/22", "10.10.148.0/22", "10.10.152.0/22"]

  # Prod-specific overrides on top of _envcommon defaults.
  one_nat_gateway_per_az = true
  enable_vpn_gateway     = false

  flow_log_cloudwatch_log_group_retention_in_days = 365

  tags = {
    Tier        = "shared"
    Criticality = "tier-1"
  }
}
