<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: always
---

# GitOps Workflow

The repo is the source of truth. The CI pipeline is the only actor that
mutates non-dev AWS accounts. Local `terraform apply` is a smell outside
sandbox accounts.

## Branching
- `main` is protected. No direct pushes. No force-push, ever.
- Feature branches: `feat/<short-slug>`, `fix/<short-slug>`, `chore/...`.
- Short-lived (≤ 2 days). Rebase on `main` before opening an MR.
- Squash-merge into `main`. The MR title becomes the commit subject.

## Merge requests (GitLab)
- Title: `<type>(<scope>): <imperative summary>` — conventional-commit style.
- Description must include: **Why**, **What**, **How verified**, **Rollback**.
- Required: 1 reviewer approval, all pipelines green, no unresolved threads.
- For IaC MRs, the `plan` job output must be linked or attached.

## Pipeline expectations
- `validate` → `plan` → `apply` (manual gate for non-dev).
- `plan` runs on every push to a branch.
- `apply` runs on `main` only, after merge, gated by environment scope.
- Rollback = revert the merge commit and let the pipeline re-apply.

## Things that are wrong, every time
- Editing AWS resources in the console for anything in a tracked account.
- Committing `*.tfstate` or `*.tfvars` (only `*.tfvars.example`).
- Bypassing protected-branch rules, even "just this once".
- Using long-lived AWS access keys in CI. Use OIDC.
