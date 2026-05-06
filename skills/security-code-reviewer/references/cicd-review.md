# CI/CD Review — Pipeline as Attack Surface

The pipeline is itself an attack surface. A compromised pipeline writes to
prod.

## Patterns to Find

- **Untrusted code with privileged secrets.** PR-from-fork triggers a
  workflow that has access to deploy keys. Fix: gate on `pull_request` (not
  `pull_request_target`) and require maintainer approval before secrets are
  exposed (`environment:` with required reviewers).
- **`pull_request_target` in GitHub Actions.** Runs in the context of the
  base branch with full secrets, but checks out the fork's code by default
  if misconfigured. Almost always wrong; if used, the workflow does not
  check out the PR ref or does so without running it.
- **`actions/checkout` of an arbitrary ref then `npm install`.** The fork's
  `package.json` runs install scripts with the privileged token in env.
  Fix: do not run untrusted install scripts in privileged jobs.
- **Pinning by tag, not by SHA.** `uses: some/action@v1` can be re-tagged
  by the action's owner. Pin to a commit SHA:
  `uses: some/action@abc123...`.
- **Secrets echoed to logs.** `echo "TOKEN=$TOKEN"`, `set -x` with secret
  envs, `curl -v` printing auth headers. Mask or do not log.
- **GitLab CI `rules: when: manual` not gating prod.** A "manual" job that
  any developer can trigger is not a control. Use protected environments
  with required approvers.
- **Self-hosted runners on public internet without isolation.** Long-lived
  runners reused across PRs leak secrets and cached creds across runs. Use
  ephemeral runners (one job per VM) or hosted runners.
- **Workflow file edits not protected.** A repo where any contributor can
  modify `.github/workflows/*.yml` and merge a self-approval is one PR away
  from secret exfiltration. Protect the path with CODEOWNERS + required
  review.
- **`permissions:` not pinned.** GitHub Actions defaults to a broad token
  scope unless the workflow declares `permissions:`. Pin to least-privilege
  per-job.
- **OIDC trust policy too broad.** An AWS role with `token.actions.githubusercontent.com`
  as the OIDC provider but `StringLike` on `sub` set to `repo:org/*:*`
  trusts every workflow in every branch of every repo in the org. Pin
  `sub` to a specific repo and ref pattern (`repo:org/repo:ref:refs/heads/main`).

## Examples

```yaml
# Vulnerable — pull_request_target with checkout of PR head
on:
  pull_request_target:
    types: [opened, synchronize]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - run: npm install && npm test
      - run: aws s3 sync ./build s3://prod-bucket/
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_KEY }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET }}

# Fixed — pull_request (not _target), gated environment for deploys,
# permissions pinned, action SHA-pinned
on:
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@8e5e7e5ab8b370d6c329ec480221332ada57f0ab
      - run: npm ci && npm test
```

```hcl
# Vulnerable — OIDC trust too broad
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gh.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:my-org/*:*"]
    }
  }
}

# Fixed — pin to a specific repo and ref
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gh.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:my-org/my-repo:ref:refs/heads/main"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
```
