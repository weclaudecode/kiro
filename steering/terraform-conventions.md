<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern: "**/*.tf"
---

# Terraform Conventions

## Versions
- Terraform `>= 1.7`. AWS provider `>= 5.0`. Pin both in
  `versions.tf`/`required_providers`.
- Bump providers as a dedicated chore MR, never bundled with feature work.

## Module structure
A reusable module has exactly these files at its root:

```
main.tf       resources
variables.tf  inputs (with description + type + validation)
outputs.tf    outputs (with description)
versions.tf   terraform + provider versions
README.md     what it does, inputs/outputs table, usage example
```

No `provider` blocks inside modules — providers are configured by the root.

## Naming
- Resources: `kebab-case` for the Terraform name, mirror the AWS resource's
  natural noun. `aws_lambda_function "ingest"`, not `"my-lambda"`.
- Variables: `snake_case`, descriptive (`vpc_id`, not `vpcid` or `id`).
- Tags: every taggable resource gets `Project`, `Environment`, `Owner`,
  `ManagedBy = "terraform"`, `Repo`, `CostCenter`. Apply via a `default_tags`
  block on the provider where possible.

## State
- Remote state in S3 with DynamoDB lock table. Per-environment state file
  keys. Encryption + versioning on the state bucket are non-negotiable.
- `terraform_remote_state` is a smell — prefer SSM Parameter Store outputs
  or data sources for cross-stack references.

## Things to avoid
- Hardcoded ARNs, account IDs, or region strings. Use `data
  "aws_caller_identity"` and `data "aws_region"`, or pass as inputs.
- `count = var.enabled ? 1 : 0` to toggle modules — use `for_each` or split
  the call site.
- `local-exec` provisioners. If you need shell, do it in CI, not in apply.
- Wrapping the AWS provider in your own module — call AWS resources directly.

## Pre-commit (recommended)
`terraform fmt -recursive`, `terraform validate`, `tflint`, `tfsec` (or
`trivy config`) on every commit.
