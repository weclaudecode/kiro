# providers.tf
# Default AWS provider plus optional aliases for cross-region work.
# default_tags applies to every resource the provider creates — set company,
# environment, and ownership tags here, not on every resource.

provider "aws" {
  region = var.region

  # Uncomment to assume a role across accounts. Prefer this over baking
  # long-lived credentials into CI.
  #
  # assume_role {
  #   role_arn     = var.assume_role_arn
  #   session_name = "terraform-${var.environment}"
  #   external_id  = var.assume_role_external_id
  # }

  default_tags {
    tags = {
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
      Repo        = var.repo_url
    }
  }
}

# Multi-region alias — uncomment when needed (CloudFront ACM certs in
# us-east-1, cross-region replication, DR replicas).
#
# provider "aws" {
#   alias  = "useast1"
#   region = "us-east-1"
#
#   default_tags {
#     tags = {
#       Environment = var.environment
#       Owner       = var.owner
#       ManagedBy   = "terraform"
#       Repo        = var.repo_url
#     }
#   }
# }
