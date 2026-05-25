# AWS resource patterns

The resources every Terraform-on-AWS author touches. AWS provider v5+ syntax.

## Provider configuration

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
```

`default_tags` is one of the most under-used AWS provider features. Set company/team tags once at the provider; do not repeat them on every resource. Resource-level `tags` merge on top of provider defaults.

### Multiple AWS providers

Cross-region resources (CloudFront ACM certs in us-east-1, replicas, DR) and cross-account resources need provider aliases:

```hcl
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

## IAM

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

## VPC

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

## Security groups

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

Note: `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` are the newer single-rule resources — also acceptable and slightly cleaner. Pick one style and use it consistently.

## KMS

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

## S3

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

If only one of these is missing, the bucket is non-compliant. This is a strong argument for wrapping the whole set in a `secure_bucket` module — see `assets/module-skeleton/`.

## EKS, RDS, ECS

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

For broader AWS architecture decisions (account topology, network strategy, service selection), defer to `aws-solution-architect`.

## Locals and helpers

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

### Account/region/partition lookups

Never hardcode account IDs, regions, or `aws` partition strings. Use data sources:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# arn:${partition}:iam::${account_id}:role/foo
```
