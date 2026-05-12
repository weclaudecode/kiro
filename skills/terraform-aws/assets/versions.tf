# versions.tf
# Pin Terraform core and every provider. Unpinned code is a time bomb.
#
# If using Terragrunt, this file still applies — Terragrunt does not generate
# versions.tf. Keep one per stack.

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
