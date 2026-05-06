# Cross-Account Auth Pattern

The pattern that scales:

1. **One bootstrap role per workload account.** Manually (or via a one-time
   CloudFormation StackSet or `scripts/bootstrap-account.sh`) create
   `TerraformExecutionRole` in every account. Trust policy allows only the
   deployment account's CI role.
2. **CI authenticates once.** GitLab/GitHub CI uses OIDC to assume
   `TerraformDeploymentRole` in the deployment account. No long-lived AWS
   keys.
3. **Generated provider chains the assume.** The root's `generate "provider"`
   block produces a provider with
   `assume_role { role_arn = "arn:aws:iam::${account_id}:role/TerraformExecutionRole" }`.
   The deployment role's identity hops into each target account per unit.
4. **Account ID flows from `account.hcl`.** Never hardcode an account ID in a
   child unit — always read it via
   `read_terragrunt_config(find_in_parent_folders("account.hcl"))`.

## Trust policy

The trust policy on `TerraformExecutionRole` in a workload account:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::DEPLOYMENT_ACCT:role/TerraformDeploymentRole" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "acme-terragrunt" }
    }
  }]
}
```

If `ExternalId` is in use, add `external_id = "acme-terragrunt"` to the
generated `assume_role` block.

For local development, engineers assume `TerraformDeploymentRole` via SSO and
run `terragrunt plan` directly — the same chain applies. For details on the
deployment-account IAM design, cross-reference the `aws-solution-architect`
skill.

## OIDC trust for the deployment role

The deployment account's `TerraformDeploymentRole` is the only role assumed
directly from CI. Its trust policy targets the GitLab OIDC provider (or
GitHub Actions equivalent):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::DEPLOYMENT_ACCT:oidc-provider/gitlab.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "gitlab.com:aud": "https://gitlab.com"
      },
      "StringLike": {
        "gitlab.com:sub": "project_path:acme/infra-live:ref_type:branch:ref:main"
      }
    }
  }]
}
```

Pin the `sub` claim to specific branches/refs. Wildcarding it across all
branches gives any MR the ability to assume the deployment role.

## Multi-region considerations

If a single unit deploys into more than one region (uncommon — prefer one
unit per region), add a second `generate "provider_secondary"` block in the
child rather than hand-writing a provider alias. The generated alias provider
should still consume `account_vars` so cross-account behaviour stays
consistent.
