# live/prod/us-east-1/region.hcl
#
# Region-scoped facts for prod in us-east-1. Inherited by every child unit
# under this directory via find_in_parent_folders("region.hcl").

locals {
  aws_region = "us-east-1"

  # Default availability zones used by network and compute units.
  azs = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
  ]

  # Region-specific endpoint overrides (rare — set when using FIPS,
  # GovCloud, or a private endpoint). Empty in this template.
  endpoints = {}

  # Region-level tag merged into default_tags.
  region_tags = {
    Region = "us-east-1"
  }
}
