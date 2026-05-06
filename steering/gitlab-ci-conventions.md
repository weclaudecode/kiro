<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern:
  - "**/.gitlab-ci.yml"
  - "**/.gitlab-ci/**/*.yml"
---

# GitLab CI Conventions

## AWS auth — OIDC only
Never long-lived AWS keys. The pipeline trades its OIDC token for STS
credentials:

```yaml
.aws_oidc: &aws_oidc
  id_tokens:
    AWS_ID_TOKEN:
      aud: https://gitlab.example.com
  before_script:
    - >
      export $(printf 'AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s'
      $(aws sts assume-role-with-web-identity
        --role-arn "$AWS_ROLE_ARN"
        --role-session-name "gitlab-${CI_PIPELINE_ID}"
        --web-identity-token "$AWS_ID_TOKEN"
        --duration-seconds 3600
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'
        --output text))
```

The trust policy on `$AWS_ROLE_ARN` restricts `sub` to the specific repo +
branch (and `ref_type=branch`).

## Stage shape
Every IaC pipeline:
1. `validate` — `terraform fmt -check`, `terragrunt hclfmt --check`,
   `tflint`, `tfsec`/`trivy config`.
2. `plan` — runs on every push, posts the plan output as an MR comment.
3. `apply` — `main` only, manual gate for non-dev environments,
   environment-scoped (`environment: prod` to gate via GitLab approvals).

## Caching
- Cache `.terragrunt-cache/` and `.terraform/` per branch + per component.
- Cache key includes the lockfile hash so a provider bump invalidates.
- `policy: pull-push` on plan, `pull` on apply.

## Artifacts
- `plan` saves the binary `tfplan` as an artifact (expire in 1 day) so
  `apply` runs the *same* plan, not a fresh one.
- Terraform JSON output goes to a `reports:terraform` artifact for the MR
  widget.

## Things to avoid
- Pipelines that `terraform apply` on every push to a branch.
- `image: latest` — pin to a digest or version tag.
- Secrets in `script:` lines (`echo`, `cat`, `set -x`). Mask + protect them.
- Running `apply` and `plan` in different runner OSes — drift in the
  generated plan.
