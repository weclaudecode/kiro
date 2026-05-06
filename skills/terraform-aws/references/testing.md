# Testing and quality gates

CI pipeline, in order:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint --recursive --enable-rule=aws_resource_missing_tags
checkov -d . --framework terraform
terraform plan -lock=false -out=tfplan   # against an empty/preview workspace
```

For wiring this into GitLab CI, see the `gitlab-pipeline` skill.

## What each tool catches

- **`terraform fmt`** enforces canonical formatting. Run with `-check` in CI, with `-recursive` to cover modules.
- **`terraform validate`** catches reference errors and type mismatches without hitting AWS. Requires `terraform init -backend=false` first.
- **`tflint`** with the AWS ruleset catches deprecated resources, missing tags, invalid instance types, and naming convention violations. `--enable-rule=aws_resource_missing_tags` is particularly valuable when default_tags is in use — it flags the resources where it cannot apply.
- **`checkov`** (or `tfsec` / `trivy config`) catches security misconfigurations: unencrypted buckets, open SGs, IAM wildcards, missing public-access blocks. Treat findings as broken-build by default; add suppressions only with a comment justifying the exception.
- **`terraform plan`** is the final gate before apply. In CI, run against a preview workspace with credentials scoped to read-only or a sandbox account.

## Module tests

For modules, two levels of test:

- **Native `terraform test` (TF 1.6+)** — unit-style. Asserts on plan output without applying. Fast, no AWS cost, runs in CI on every PR.
- **`terratest` (Go)** — integration. Actually applies into a sandbox account, asserts via AWS SDK calls, destroys. Slow, costs money, runs nightly or on release tags. Worth it for high-blast-radius modules (VPC, EKS, IAM platform).

### `terraform test` example

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

Use `command = plan` for fast assertions on computed values. Use `command = apply` only for runs that actually need to provision, and target a sandbox account.

### `terratest` example sketch

```go
func TestVPC(t *testing.T) {
  opts := &terraform.Options{
    TerraformDir: "../examples/basic",
    Vars: map[string]interface{}{
      "name": "tg-test-" + random.UniqueId(),
    },
  }
  defer terraform.Destroy(t, opts)
  terraform.InitAndApply(t, opts)

  vpcId := terraform.Output(t, opts, "vpc_id")
  vpc := aws.GetVpcById(t, vpcId, "us-east-1")
  assert.Equal(t, "10.40.0.0/16", *vpc.CidrBlock)
}
```

Reserve terratest for modules whose breakage is expensive: VPC, EKS, IAM scaffolding, anything shared across many services.

## Pre-commit hooks

Local pre-commit hooks should mirror the CI gates: `terraform fmt`, `terraform validate`, and `tflint`. The `pre-commit-terraform` project bundles these. Keeping them in pre-commit catches issues before push and reduces wasted CI minutes.
