# tagged-bucket

A reference Terraform module that provisions a single S3 bucket with the full v4-split sibling resources required for security compliance:

- Bucket ownership controls (`BucketOwnerEnforced`)
- Full public access block
- Versioning enabled
- Server-side encryption (SSE-KMS when a key ARN is supplied, otherwise SSE-S3)
- Lifecycle rule that expires noncurrent versions and aborts incomplete multipart uploads
- Bucket policy denying non-TLS access

It is intended as a starting point for a real internal `secure_bucket` module — copy it, rename it, and extend with the controls specific to the team (replication, access logging targets, object lock, intelligent tiering).

## Usage

```hcl
module "data_bucket" {
  source = "git::ssh://git@gitlab.com/acme/terraform-modules.git//tagged-bucket?ref=v0.1.0"

  name        = "events"
  name_prefix = "prod-platform"

  kms_key_arn                        = aws_kms_key.data.arn
  noncurrent_version_expiration_days = 365
  force_destroy                      = false

  tags = {
    DataClassification = "internal"
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Logical name for the bucket. 3-40 chars, lowercase alphanumeric and hyphens. |
| `name_prefix` | `string` | required | Prefix prepended to the bucket name (e.g. environment-app). |
| `kms_key_arn` | `string` | `null` | KMS key ARN for SSE-KMS. If null, the bucket uses SSE-S3 (AES256). |
| `noncurrent_version_expiration_days` | `number` | `90` | Days before noncurrent versions expire. 1-3650. |
| `force_destroy` | `bool` | `false` | Allow `terraform destroy` to delete a non-empty bucket. Keep false in prod. |
| `tags` | `map(string)` | `{}` | Additional tags merged on top of provider default_tags. |

## Outputs

| Name | Description |
|---|---|
| `id` | Bucket name (also the bucket ID). |
| `arn` | Bucket ARN, suitable for use in IAM policies. |
| `bucket_domain_name` | Bucket domain name (DNS). |
| `bucket_regional_domain_name` | Regional bucket domain name, for CloudFront origins or VPC endpoints. |

## Requirements

| Name | Version |
|---|---|
| terraform | `>= 1.9.0, < 2.0.0` |
| aws | `~> 5.70` |

## Notes

- The bucket name is composed as `${name_prefix}-${name}`. AWS S3 bucket names are globally unique; pick a `name_prefix` that includes account or environment to avoid collisions.
- `force_destroy = true` is convenient for `dev` stacks but dangerous in prod — set it `false` and pair with `lifecycle { prevent_destroy = true }` on the calling resource if the bucket holds data of record.
- For multi-region replication, extend the module with a `replication_configuration` block and accept an aliased provider for the destination.
