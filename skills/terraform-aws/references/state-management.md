# State management

Local state (`terraform.tfstate` on disk) is acceptable only for personal experiments. For anything shared, use S3 + DynamoDB.

## Backend configuration

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

## State bucket requirements

The bucket itself is bootstrapped once (typically via `scripts/bootstrap-backend.sh`, or via a separate small Terraform stack with local state, then migrated). It needs:

- **Versioning enabled** — recovery from accidental `terraform destroy` or corrupt state
- **KMS encryption** — the state file contains every resource attribute, including RDS passwords (yes, even with `sensitive`), IAM access keys, secret ARNs, and full configuration
- **Public access block** — all four flags `true`
- **Access logging** to a separate logging bucket
- **Bucket policy** that denies non-TLS access and restricts to specific IAM principals
- **Object Lock or MFA-delete** for prod state if the threat model warrants it

## Lock table

DynamoDB lock table needs a `LockID` string partition key and nothing else. PAY_PER_REQUEST billing is enough for any real workload because locks are short-lived.

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

## State sensitivity

The state file holds every attribute of every managed resource — including values flagged `sensitive = true`, RDS master passwords, IAM access keys, and any data fetched via data sources. Treat the state bucket like a vault.

## Reading state from elsewhere

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

## Secrets in state

Never write secrets to `.tf` files, `.tfvars` files, or environment-specific config that gets committed. Never assume `sensitive = true` keeps something out of state — it does not.

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

## State surgery safety

Before any `terraform state rm` or `terraform state mv`: take a state backup (`terraform state pull > backup.tfstate`) and confirm the lock table shows your lock. Prefer the in-code `moved`, `import`, and `removed` blocks over raw CLI state surgery — see `lifecycle-and-meta.md`.
