---
name: terraform-aws
description: Use when writing or reviewing Terraform code that provisions AWS resources — covers project structure, remote state on S3+DynamoDB, module design, provider configuration, AWS-specific patterns (IAM, VPC, KMS), variable validation, lifecycle and meta-arguments, drift management, and testing with terraform validate, tflint, checkov, and terratest
---

# Terraform for AWS

## Overview

Terraform is a declarative graph executor with a stateful side effect. Authors write desired state in HCL, Terraform builds a directed acyclic graph of resources, then walks that graph to make API calls that move the world toward the declaration. The state file is the bridge between code and reality. Most production failures come from misunderstanding either the graph (cycles, implicit ordering, surprising replacements) or the state (lost locks, drift, secrets in plaintext) — not from HCL syntax.

This skill covers Terraform itself plus AWS-specific patterns. For multi-account orchestration, environment promotion, and DRY composition across stacks, see the companion `terragrunt-multi-account` skill.

## When to Use

Trigger this skill when:

- Writing a new Terraform module or root configuration that targets AWS
- Reviewing a Terraform PR for AWS resources
- Debugging drift, plan churn, or surprise replacements
- Designing the layout for a fresh Terraform repo
- Migrating local state to a remote backend
- Adding a new AWS resource type and unsure of the canonical pattern (S3 split, IAM separation, SG rule resources)

Do NOT use this skill for:

- Multi-account orchestration, environment-per-folder layouts, or DRY-via-Terragrunt — see `terragrunt-multi-account`
- Pure CloudFormation, CDK, or Pulumi work
- Application code or business logic

## Project layout

The single-environment standard. Every root module looks like this:

```
.
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf       # terraform + provider version pins
├── providers.tf      # provider configuration, default_tags, aliases
├── data.tf           # data sources (caller_identity, AMIs, hosted zones)
├── locals.tf         # naming, derived maps
├── terraform.tfvars  # gitignored when it contains environment values
└── modules/
    └── <name>/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── versions.tf
        └── README.md
```

One giant `main.tf` is fine for a tutorial and wrong for anything else. Once a root module has more than ~150 lines, split by AWS service domain: `iam.tf`, `vpc.tf`, `s3.tf`, `kms.tf`, `rds.tf`. The split is purely organizational — Terraform concatenates all `.tf` files in a directory before parsing, so file names have no semantic meaning. Use this freedom to make code reviewable.

Split by file when the resources still belong to one logical stack. Split into a `modules/` subdirectory when there is a reusable unit (a network, a service, a cluster) — see Modules below.

## Versions and providers

Always pin. Unpinned Terraform code is a time bomb.

```hcl
# versions.tf
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
```

The `~>` operator (pessimistic constraint) allows the rightmost version component to increment. `~> 5.70` accepts `5.70.x`, `5.71.x`, up to but not including `6.0.0`. That is the right level of trust for the AWS provider: bug fixes and new resources flow in, breaking majors do not.

Never use `version = ">= 5.0"` with no upper bound, and never omit the version. Both will eventually pull a major release that renames or removes resources mid-sprint.

`required_version` for Terraform itself should match what CI uses; bump it when adopting new core features (`import` blocks, `removed` blocks, `terraform test`).

### Multiple AWS providers

Cross-region resources (CloudFront ACM certs in us-east-1, replicas, DR) and cross-account resources need provider aliases:

```hcl
# providers.tf
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
      Repo        = var.repo_url
    }
  }
}

provider "aws" {
  alias  = "useast1"
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
      Repo        = var.repo_url
    }
  }
}

# Example: CloudFront certificate must live in us-east-1
resource "aws_acm_certificate" "cdn" {
  provider          = aws.useast1
  domain_name       = var.domain
  validation_method = "DNS"
}
```

`default_tags` is one of the most under-used AWS provider features. Set company/team tags once at the provider; do not repeat them on every resource. Resource-level `tags` merge on top of provider defaults.

## State management

Local state (`terraform.tfstate` on disk) is acceptable only for personal experiments. For anything shared, use S3 + DynamoDB.

```hcl
# backend.tf — bootstrap separately, then reference here
terraform {
  backend "s3" {
    bucket         = "acme-tfstate-prod"
    key            = "platform/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "acme-tfstate-locks"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-1:111111111111:key/abcd-..."
  }
}
```

The bucket itself is bootstrapped once (typically via a separate small Terraform stack with local state, then migrated, or via the AWS CLI). It needs:

- **Versioning enabled** — recovery from accidental `terraform destroy` or corrupt state
- **KMS encryption** — the state file contains every resource attribute, including RDS passwords (yes, even with `sensitive`), IAM access keys, secret ARNs, and full configuration
- **Public access block** — all four flags `true`
- **Access logging** to a separate logging bucket
- **Bucket policy** that denies non-TLS access and restricts to specific IAM principals
- **Object Lock or MFA-delete** for prod state if the threat model warrants it

DynamoDB lock table needs a `LockID` string partition key and nothing else. Provisioned-capacity 1/1 is enough for any real workload because locks are short-lived.

```hcl
resource "aws_dynamodb_table" "locks" {
  name         = "acme-tfstate-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
```

Without the lock table, two engineers running `apply` simultaneously will corrupt state. This is not theoretical.

### Reading state from elsewhere

To read outputs from another stack, two options:

```hcl
# Option 1: terraform_remote_state — tight coupling, but typed
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "acme-tfstate-prod"
    key    = "platform/network/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "aws_instance" "app" {
  subnet_id = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
}
```

```hcl
# Option 2: SSM Parameter Store — loose coupling, plus accessible to non-TF tools
data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/platform/network/private_subnet_ids"
}

resource "aws_instance" "app" {
  subnet_id = split(",", data.aws_ssm_parameter.private_subnet_ids.value)[0]
}
```

`terraform_remote_state` requires the consumer to have read access to the producer's state bucket, which leaks more than the outputs. SSM (or a published JSON contract) is usually the better answer for cross-team boundaries. Use `terraform_remote_state` within a single team's own stacks.

## Modules

A module is a unit of reuse. Three rules for when to make one:

1. **Repeated three times or more.** First time, write inline. Second time, copy. Third time, refactor into a module. Premature module-ization causes more pain than it saves.
2. **Represents a logical unit.** A VPC, an ECS service, an EKS cluster, a "standard S3 bucket" with all the security controls. These are real abstractions worth a module even on first use.
3. **NOT a trivial wrapper.** A module that takes the same inputs as `aws_s3_bucket` and just passes them through is a tax, not an abstraction.

### Inputs

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

### Outputs

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

### Module sources and versioning

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

### Provider passing

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

### Composition over nesting

Three levels of module nesting (root → wrapper → component → primitive) is the limit before debugging becomes painful. Prefer composition: the root calls multiple flat modules and wires their outputs together, rather than one mega-module that wraps everything.

## Variables

Always type. Untyped variables default to `any` and silently accept malformed input.

```hcl
variable "instance_size" {
  type    = string
  default = "t3.medium"

  validation {
    condition     = contains(["t3.medium", "t3.large", "m6i.large"], var.instance_size)
    error_message = "instance_size must be one of the approved sizes."
  }
}

variable "vpc_config" {
  type = object({
    cidr             = string
    enable_flow_logs = optional(bool, true)
    azs              = optional(list(string))
  })
}

variable "db_password" {
  type      = string
  sensitive = true
  nullable  = false
}
```

Use `optional()` (TF 1.3+) inside object types for partial structs with defaults — much cleaner than splitting one logical input into three flat variables.

`sensitive = true` redacts the value from plan output and CLI logs (not from state — see Secrets). `nullable = false` rejects `null`, useful for required-with-no-default semantics.

## Locals and expressions

Locals are for derived values, naming conventions, and computed maps. They make the rest of the code readable.

```hcl
locals {
  name_prefix = "${var.environment}-${var.app}"

  common_tags = {
    Application = var.app
    CostCenter  = var.cost_center
  }

  subnet_map = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.vpc_cidr, 4, idx)
  }
}
```

### `for_each` over `count`

Both create multiple resources. They are not equivalent.

`count = length(var.names)` indexes resources by integer position. Removing the middle element shifts every index after it, and Terraform plans destroy-and-recreate for everything that shifted. This is the cause of most "why is it replacing 47 things" plan reviews.

`for_each = toset(var.names)` keys resources by string. Removing one entry destroys exactly that one; the others are unaffected.

Use `count` only for the boolean toggle pattern (`count = var.enabled ? 1 : 0`). Anything else, use `for_each`.

```hcl
resource "aws_iam_user" "engineers" {
  for_each = toset(var.engineer_usernames)
  name     = each.value
}
```

### `try()` and `can()`

Resilient lookups for optional inputs and sometimes-nested data:

```hcl
locals {
  log_retention = try(var.logging.retention_days, 30)
  has_logging   = can(var.logging.bucket_arn)
}
```

## AWS-specific patterns

The resources every Terraform-on-AWS author touches.

### IAM

Build policies with the data source, not inline JSON heredocs. The data source validates syntax, supports interpolation cleanly, and renders in plan output:

```hcl
data "aws_iam_policy_document" "app_s3" {
  statement {
    sid     = "ReadWriteOwnPrefix"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.app.arn}/${var.tenant_id}/*",
    ]
  }

  statement {
    sid       = "ListOwnPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.tenant_id}/*"]
    }
  }
}

resource "aws_iam_policy" "app_s3" {
  name   = "${local.name_prefix}-app-s3"
  policy = data.aws_iam_policy_document.app_s3.json
}

resource "aws_iam_role" "app" {
  name               = "${local.name_prefix}-app"
  assume_role_policy = data.aws_iam_policy_document.app_assume.json
}

resource "aws_iam_role_policy_attachment" "app_s3" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_s3.arn
}
```

Always separate `aws_iam_role` + `aws_iam_policy` + `aws_iam_role_policy_attachment`. Do not use `aws_iam_role_policy` (inline policy on the role). Inline policies hide in `terraform show` output, cannot be reused, and obscure least-privilege review.

### VPC

For 95% of cases, `terraform-aws-modules/vpc/aws` is the right answer:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.name_prefix}-vpc"
  cidr = "10.40.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.40.1.0/24", "10.40.2.0/24", "10.40.3.0/24"]
  public_subnets  = ["10.40.101.0/24", "10.40.102.0/24", "10.40.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
}
```

Roll a custom VPC module only when the standard one cannot express the requirement (multi-CIDR, complex peering, transit gateway attachments with non-standard topology). Never use the default VPC for anything Terraform-managed.

### Security groups

Always use separate `aws_security_group_rule` resources, never inline `ingress`/`egress` blocks:

```hcl
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app"
  description = "App tier"
  vpc_id      = module.vpc.vpc_id
  # NO ingress/egress here
}

resource "aws_security_group_rule" "app_ingress_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.alb.id
  description              = "ALB to app"
}

resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.app.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All egress"
}
```

Inline blocks make rules unmanageable: another module cannot add a rule to the SG without owning the entire definition. Separate rule resources compose.

(Note: `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` are the newer single-rule resources — also acceptable and slightly cleaner. Pick one style and use it consistently.)

### KMS

One key per logical purpose: one for state, one for RDS, one for S3 logs, one for application secrets. Mixing purposes in one key makes rotation and revocation messy.

```hcl
data "aws_iam_policy_document" "secrets_key" {
  statement {
    sid     = "EnableRoot"
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }

  statement {
    sid     = "AppDecrypt"
    effect  = "Allow"
    actions = ["kms:Decrypt", "kms:DescribeKey"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.app.arn]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "secrets" {
  description             = "Application secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.secrets_key.json
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
```

`enable_key_rotation = true` is non-negotiable for new keys.

### S3

The AWS provider v4 split broke `aws_s3_bucket` into many sibling resources. A bucket needs all of them:

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "${local.name_prefix}-data"
}

resource "aws_s3_bucket_ownership_controls" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
```

If only one of these is missing, the bucket is non-compliant. This is a strong argument for wrapping the whole set in a `secure_bucket` module.

### EKS, RDS, ECS

Use community modules and pin them. Do not write these from primitives unless there is a specific reason:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"
  # ...
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.10"
  # ...
}
```

The community modules encode dozens of person-years of edge cases (IRSA wiring, parameter groups, snapshot lifecycle). Reinventing them is a tax.

## Lifecycle and meta-arguments

### `create_before_destroy`

For replacement-sensitive resources, force the new one to exist before the old is destroyed:

```hcl
resource "aws_launch_template" "app" {
  name_prefix = "${local.name_prefix}-app-"
  # ...

  lifecycle {
    create_before_destroy = true
  }
}
```

Required for: ASG launch templates (so the ASG can shift), IAM policies attached to live roles (so attachment never points at a dead policy), Route53 records during a rename, ALB listeners.

### `prevent_destroy`

For stateful resources where accidental destroy is catastrophic:

```hcl
resource "aws_db_instance" "primary" {
  # ...

  lifecycle {
    prevent_destroy = true
  }
}
```

Foot-gun: when intentionally retiring the resource, the `prevent_destroy = true` line must be removed first, then `terraform apply`, then a second `apply` to actually destroy. Plan failure with "this resource cannot be destroyed" is the guard working as intended.

### `ignore_changes`

For fields legitimately modified outside Terraform:

```hcl
resource "aws_autoscaling_group" "app" {
  # ...

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_ecs_service" "app" {
  # ...

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}
```

Common: ASG `desired_capacity` (managed by autoscaling policies), ECS `desired_count` and `task_definition` (managed by deploy tool), tag keys added by AWS Config or Backup.

Never use `ignore_changes = ["*"]` or `ignore_changes = all`. That is a confession that no one understands what the resource does.

### `depends_on`

Should be rare. Real attribute references (`aws_subnet.foo.id`) create implicit dependencies that Terraform tracks correctly. Use explicit `depends_on` only when the dependency is invisible at the attribute level — e.g., an IAM policy that grants permissions used at resource creation time but is not referenced by ARN.

### `moved` blocks

Refactor without destroy/recreate. Renaming a resource or moving it into a module:

```hcl
moved {
  from = aws_instance.app
  to   = module.compute.aws_instance.app
}
```

After the next apply, the `moved` block can be removed. This replaces the legacy `terraform state mv` workflow for in-code refactors.

### `import` blocks (TF 1.5+)

Code-reviewable imports:

```hcl
import {
  to = aws_iam_role.legacy
  id = "legacy-app-role"
}

resource "aws_iam_role" "legacy" {
  name               = "legacy-app-role"
  assume_role_policy = data.aws_iam_policy_document.legacy_assume.json
}
```

Plan shows the import; apply executes it. PR reviewers see what was imported. Far better than running `terraform import` from a developer laptop with no audit trail.

### `removed` blocks (TF 1.7+)

Drop a resource from state without destroying the underlying AWS resource:

```hcl
removed {
  from = aws_iam_role.deprecated

  lifecycle {
    destroy = false
  }
}
```

Useful when handing a resource over to another stack or to manual ownership.

## Drift and refactoring

`terraform plan` prints three signals: create (`+`), update in place (`~`), replace (`-/+`). Read replacements carefully — the line annotated `# forces replacement` names the field that triggered it.

`terraform plan -refresh-only` reads current AWS state and shows drift without proposing changes. Run this after suspicious incidents (a console click, a runbook action) to see exactly what diverged.

When drift is found:

1. **The console change was correct** — fold it into Terraform code, run `terraform apply` (no-op against the now-correct world).
2. **The console change was wrong** — `terraform apply` reverts it. Tell whoever made the change.
3. **The field is legitimately externally managed** — add it to `lifecycle.ignore_changes`.

For renaming, use a `moved` block. For removing from state without destroying, use a `removed` block. For pulling in a resource AWS already owns, use an `import` block. The CLI commands `terraform state mv`, `terraform state rm`, and `terraform import` still work but bypass code review — prefer the block forms.

Before any `terraform state rm` or `terraform state mv`: take a state backup (`terraform state pull > backup.tfstate`) and confirm the lock table shows your lock.

## Testing and quality gates

CI pipeline, in order:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint --recursive --enable-rule=aws_resource_missing_tags
checkov -d . --framework terraform
terraform plan -lock=false -out=tfplan   # against an empty/preview workspace
```

`terraform fmt` enforces canonical formatting. `terraform validate` catches reference errors and type mismatches without hitting AWS. `tflint` with the AWS ruleset catches deprecated resources, missing tags, invalid instance types, and naming convention violations. `checkov` (or `tfsec` / `trivy config`) catches security misconfigurations: unencrypted buckets, open SGs, IAM wildcards.

For modules, two levels of test:

- **Native `terraform test` (TF 1.6+)** — unit-style. Asserts on plan output without applying. Fast, no AWS cost, runs in CI on every PR.
- **`terratest` (Go)** — integration. Actually applies into a sandbox account, asserts via AWS SDK calls, destroys. Slow, costs money, runs nightly or on release tags. Worth it for high-blast-radius modules (VPC, EKS, IAM platform).

```hcl
# tests/main.tftest.hcl
run "validate_naming" {
  command = plan

  variables {
    name        = "test-bucket"
    environment = "dev"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "dev-test-bucket"
    error_message = "bucket name did not match expected naming pattern"
  }
}
```

## Secrets

Never write secrets to `.tf` files, `.tfvars` files, or environment-specific config that gets committed. Never assume `sensitive = true` keeps something out of state — it does not. The state file holds the real value in plaintext.

Source secrets at apply time from AWS-native stores:

```hcl
data "aws_secretsmanager_secret_version" "db_master" {
  secret_id = "rds/${var.environment}/master"
}

resource "aws_db_instance" "main" {
  username = "admin"
  password = jsondecode(data.aws_secretsmanager_secret_version.db_master.secret_string)["password"]
  # ...
}
```

Or `aws_ssm_parameter` with `with_decryption = true`. Or pass via `TF_VAR_db_password` from a CI step that pulls from a vault.

The state still ends up containing the password, which is why the state bucket itself must be KMS-encrypted with a tightly-scoped key policy. The principle is: secrets travel through Terraform but never originate in Terraform code.

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
