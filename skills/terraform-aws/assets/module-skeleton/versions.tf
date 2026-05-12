# versions.tf
# Module-level pins. The module declares its own provider requirements;
# the root module is responsible for satisfying them.

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
