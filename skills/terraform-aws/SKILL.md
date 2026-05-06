---
name: terraform-aws
description: Use when writing or reviewing Terraform code that provisions AWS resources — covers project structure, remote state on S3+DynamoDB, module design, provider configuration, AWS-specific patterns (IAM, VPC, KMS), variable validation, lifecycle and meta-arguments, drift management, and testing with terraform validate, tflint, checkov, and terratest
---

# Terraform for AWS

## Overview

Terraform is a declarative graph executor with a stateful side effect: authors write desired state in HCL, Terraform builds a directed acyclic graph and walks it making API calls, and the state file is the bridge between code and reality. Most production failures come from misunderstanding the state or the resource graph (lost locks, drift, surprise replacements, secrets in plaintext) — not from HCL syntax. This skill focuses on the patterns that survive contact with real AWS accounts.

## When to Use

Use this skill when:

- Writing a new Terraform module or root configuration that targets AWS
- Reviewing a Terraform PR for AWS resources
- Debugging drift, plan churn, or surprise replacements
- Designing the layout for a fresh Terraform repo
- Migrating local state to a remote backend
- Adding a new AWS resource type and unsure of the canonical pattern (S3 split, IAM separation, SG rule resources)

Do not use this skill for:

- Multi-account orchestration, environment-per-folder layouts, or DRY-via-Terragrunt — see `terragrunt-multi-account`
- High-level AWS architecture decisions (account topology, service selection, network strategy) — see `aws-solution-architect`
- CI pipeline wiring for `terraform fmt`/`validate`/`plan` — see `gitlab-pipeline`
- Pure CloudFormation, CDK, or Pulumi work
- Application code or business logic

## Non-negotiables

- Pin Terraform core and every provider. `~> 5.70` for AWS, never `>= 5.0` and never unset.
- Remote state on S3 + DynamoDB lock table. Local state is for personal experiments only.
- `for_each` over `count` for collections of named things. Reserve `count` for the `var.enabled ? 1 : 0` toggle.
- Separate `aws_security_group_rule` and `aws_iam_role_policy_attachment` resources. No inline `ingress`/`egress` blocks, no `aws_iam_role_policy`.
- `data.aws_iam_policy_document` for every policy — not JSON heredocs.
- `default_tags` set once on the AWS provider; resource-level `tags` only for additions.
- Never hardcode account IDs or partition strings. Use `data.aws_caller_identity` and `data.aws_partition`.

## Project skeleton

`templates/` contains a ready-to-copy single-environment root module:

| File | Purpose |
|---|---|
| `versions.tf` | Terraform core and provider version pins |
| `providers.tf` | AWS provider with `default_tags`; commented `assume_role` and multi-region alias |
| `backend.tf` | S3 + DynamoDB backend skeleton; comments for the Terragrunt case |
| `main.tf` | Minimal example resource (tagged S3 bucket via the v4 split pattern) |
| `variables.tf` | Validated string, number with bounds, object with `optional()`, sensitive variable |
| `outputs.tf` | Description and `sensitive` flagging where relevant |
| `.gitignore` | Standard Terraform ignores plus `.tfvars` warning |

For when to split files versus extract a module, see `references/project-layout.md`.

## Module skeleton

`templates/module-skeleton/` is a complete sample module — a "tagged-bucket" with `versions.tf`, `variables.tf` (with `validation` blocks), `main.tf` (correct S3 sibling resources, TLS-only bucket policy, lifecycle rule), `outputs.tf`, and a `README.md` documenting inputs, outputs, and a usage example.

For module design rules (when to extract, sources, versioning, provider passing, composition), see `references/modules.md`.

## Bootstrap

`scripts/bootstrap-backend.sh` is an idempotent bash script that creates the S3 state bucket (versioned, encrypted, public-access-blocked, optional access logging) and the DynamoDB lock table (`LockID` PK, PAY_PER_REQUEST). `set -euo pipefail`, every step checks for existing resources, configurable via environment variables, prints the matching `backend "s3"` block at the end.

## References

| File | Covers |
|---|---|
| `references/project-layout.md` | File structure, when to split, when to extract a module |
| `references/state-management.md` | S3 + DynamoDB backend, sensitivity, `terraform_remote_state` vs SSM, secrets |
| `references/modules.md` | Inputs/outputs/versioning, provider passing, composition |
| `references/aws-resources.md` | IAM, VPC, security groups, KMS, S3 patterns, locals, `for_each` |
| `references/lifecycle-and-meta.md` | `lifecycle`, `moved`/`import`/`removed` blocks, drift workflow |
| `references/testing.md` | `validate`, `tflint`, `checkov`, `terraform test`, `terratest` |

## Common Mistakes

| Mistake | Why it bites | Fix |
|---|---|---|
| `count` for collections of named things | One removal reorders every index after it; Terraform plans unnecessary destroys | `for_each` keyed by name |
| Inline `ingress`/`egress` in `aws_security_group` | Cannot compose rules from multiple modules | Separate `aws_security_group_rule` resources |
| Module takes `region` and ignores it | Resources land in the provider's region; the variable is a lie | Either accept aliased provider or remove the input |
| State bucket without versioning + KMS | Lost state file = lost infra; plaintext state = leaked secrets | Versioning + KMS + access logs + bucket policy |
| No DynamoDB lock table | Concurrent applies corrupt state | Lock table with `LockID` PK |
| `aws_iam_role_policy` inline | Policy hidden from review tools, not reusable | `aws_iam_policy` + `aws_iam_role_policy_attachment` |
| Hardcoded account IDs / ARNs | Breaks on every account move; un-grep-able | `data.aws_caller_identity.current.account_id`, `data.aws_partition.current.partition` |
| `lifecycle.ignore_changes = ["*"]` | Hides all drift forever | Name specific fields, or fix the underlying churn |
| Provider unpinned (`>= 5.0`) | Major bumps will break apply mid-sprint | `~> 5.70` |
| Default VPC for anything | No flow logs, public subnets, shared with everything | Custom VPC via `terraform-aws-modules/vpc/aws` |
| RDS password in `terraform.tfvars` | Committed to git, in plaintext, forever | Secrets Manager / SSM Parameter Store via data source |
| Branch reference in module source (`?ref=main`) | Module changes silently break consumers | Pin to tag (`?ref=v1.4.2`) |
| `terraform import` from laptop | No audit trail, no review | `import` block in code |

## Quick Reference

| Need | Use |
|---|---|
| Build IAM policy JSON | `data "aws_iam_policy_document"` |
| Get current account ID / region / partition | `data "aws_caller_identity"`, `data "aws_region"`, `data "aws_partition"` |
| Multiple resources by name | `for_each = toset(var.names)` or `for_each = { for k, v in var.things : k => v }` |
| Conditional resource | `count = var.enabled ? 1 : 0` |
| Cross-region resource | Provider alias + `provider = aws.useast1` |
| Rename without destroy | `moved` block |
| Adopt existing AWS resource | `import` block |
| Drop from state, keep in AWS | `removed` block with `lifecycle.destroy = false` |
| Force new before destroy | `lifecycle.create_before_destroy = true` |
| Protect stateful resource | `lifecycle.prevent_destroy = true` |
| Allow external mutation of a field | `lifecycle.ignore_changes = [field]` |
| Read another stack's outputs | `terraform_remote_state` or SSM Parameter Store |
| Standard VPC | `terraform-aws-modules/vpc/aws` |
| Standard EKS / RDS | `terraform-aws-modules/eks/aws`, `terraform-aws-modules/rds/aws` |
| Multi-account / multi-env orchestration | See `terragrunt-multi-account` skill |
