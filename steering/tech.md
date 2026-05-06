<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: always
---

# Tech Stack

This workstation and the projects it touches target the following stack.
Assume these defaults unless a project's own steering says otherwise.

## Cloud & runtime
- **Cloud:** AWS. Primary region varies by project; never hardcode it — read
  from `AWS_REGION` or a Terragrunt input.
- **Compute:** AWS Lambda (Python 3.12 runtime, `arm64` by default).
- **Storage:** S3 for objects, DynamoDB for low-latency KV, RDS Aurora
  PostgreSQL when relational.
- **Messaging:** EventBridge, SQS, SNS. Prefer event-driven over polling.
- **Observability:** CloudWatch Logs + Metrics, AWS X-Ray, Lambda Powertools.

## Languages & tools
- **Python 3.12** with `uv` for env + dependency management.
- **Linters/typecheckers:** `ruff` (lint + format), `mypy --strict`.
- **Tests:** `pytest` only. No `unittest`-style classes in new code.
- **IaC:** Terraform `>= 1.7` + Terragrunt `>= 0.55`. AWS provider `>= 5.0`.
- **CI/CD:** GitLab CI/CD with self-managed runners. OIDC to AWS — never
  long-lived access keys.
- **Workstation:** Linux (Ubuntu/Debian assumed for shell snippets).

## Workflow
- **GitOps.** Every environment change goes through an MR. The pipeline is
  the only thing that touches AWS in non-dev accounts.
- **Conventional commits** (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`,
  `test:`, `ci:`).
- **Trunk-based**, short-lived feature branches, squash-merge to `main`.

## What "good" looks like in one line
Reproducible, observable, least-privileged, and recoverable from `main` alone.
