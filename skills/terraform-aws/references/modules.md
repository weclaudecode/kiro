# Module design

A module is a unit of reuse. Three rules for when to make one:

1. **Repeated three times or more.** First time, write inline. Second time, copy. Third time, refactor into a module. Premature module-ization causes more pain than it saves.
2. **Represents a logical unit.** A VPC, an ECS service, an EKS cluster, a "standard S3 bucket" with all the security controls. These are real abstractions worth a module even on first use.
3. **NOT a trivial wrapper.** A module that takes the same inputs as `aws_s3_bucket` and just passes them through is a tax, not an abstraction.

A complete module skeleton lives in `templates/module-skeleton/`.

## Inputs

Minimal, validated, typed:

```hcl
variable "name" {
  description = "Logical name for the bucket; will be prefixed with environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars, lowercase alphanumeric + hyphens."
  }
}

variable "lifecycle_days" {
  description = "Days before noncurrent versions transition to Glacier."
  type        = number
  default     = 90

  validation {
    condition     = var.lifecycle_days >= 30 && var.lifecycle_days <= 3650
    error_message = "lifecycle_days must be between 30 and 3650."
  }
}

variable "tags" {
  description = "Additional tags merged on top of provider default_tags."
  type        = map(string)
  default     = {}
}
```

Always type. Untyped variables default to `any` and silently accept malformed input.

Use `optional()` (TF 1.3+) inside object types for partial structs with defaults — much cleaner than splitting one logical input into three flat variables.

```hcl
variable "vpc_config" {
  type = object({
    cidr             = string
    enable_flow_logs = optional(bool, true)
    azs              = optional(list(string))
  })
}
```

`sensitive = true` redacts the value from plan output and CLI logs (not from state). `nullable = false` rejects `null`, useful for required-with-no-default semantics.

## Outputs

Expose every consumable attribute callers will reasonably need: ARNs, IDs, names, endpoints. Do not expose internal IDs callers should not depend on (e.g., the ID of an internal IAM policy used only inside the module — that is implementation detail).

```hcl
output "bucket_id" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN, suitable for IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain, for CloudFront origin or VPC endpoint."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
```

## Sources and versioning

Pin module versions the same way as providers. The Git-tag pattern:

```hcl
module "vpc" {
  source = "git::ssh://git@gitlab.com/acme/terraform-modules.git//vpc?ref=v1.4.2"

  name = "platform"
  cidr = "10.40.0.0/16"
}
```

Or the Terraform Registry:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"
}
```

Never use a branch name (`?ref=main`) as a source. That is the module equivalent of `version = "latest"` and will silently break apply.

## Provider passing

Modules inherit providers by default. Only pass them explicitly when the module needs multiple regions or aliased providers:

```hcl
module "global_cdn" {
  source = "./modules/cdn"

  providers = {
    aws         = aws            # for non-cert resources
    aws.useast1 = aws.useast1    # for the ACM cert
  }
}
```

The module declares the alias requirement in its own `versions.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.70"
      configuration_aliases = [aws.useast1]
    }
  }
}
```

## Composition over nesting

Three levels of module nesting (root → wrapper → component → primitive) is the limit before debugging becomes painful. Prefer composition: the root calls multiple flat modules and wires their outputs together, rather than one mega-module that wraps everything.

For multi-stack orchestration, see `terragrunt-multi-account` rather than reaching for deeper nesting.

## Documenting a module

Every module ships a `README.md` documenting:

- **Purpose** — one sentence on what it provisions
- **Usage** — a copy-pasteable HCL example
- **Inputs** — table of name, type, default, description
- **Outputs** — table of name, description
- **Requirements** — Terraform version, provider versions, required aliases

`terraform-docs` can generate the inputs/outputs tables automatically from the module source.
