<!-- Install to: ~/.kiro/prompts/  OR  <project>/.kiro/prompts/ -->
<!-- Invoke as: @review-iac -->

Review the Terraform / Terragrunt diff on the current branch against `main`.

Steps:
1. `git fetch origin main && git diff origin/main...HEAD -- '*.tf' '*.hcl'`
2. For each changed file, read the surrounding context (the rest of the
   module, sibling components, the parent `_envcommon` or `terragrunt.hcl`).
3. If feasible, run `terraform fmt -check -recursive` on changed dirs and
   `terragrunt hclfmt --check` on changed `*.hcl`. Note any failures.

Apply this checklist:

**Correctness**
- [ ] `terraform plan` would succeed (no missing inputs, no type mismatches)
- [ ] Any `force_new`-triggering attribute changes are intentional
- [ ] No `count`/`for_each` toggle that orphans state on flip

**Security** (cross-check `aws-security.md` steering)
- [ ] No `Action: "*"` + `Resource: "*"` in any IAM policy
- [ ] All taggable resources have the required tags
- [ ] Encryption: S3 buckets, EBS volumes, RDS storage, SSM SecureString
- [ ] No `0.0.0.0/0` SG rule on a port other than 443 (and only on a public ALB)

**Convention** (cross-check `terraform-conventions.md`, `terragrunt-conventions.md`)
- [ ] Module structure (`main`/`variables`/`outputs`/`versions`/`README`)
- [ ] No `provider` block inside a reusable module
- [ ] Terragrunt leaf is thin (include + source + inputs)
- [ ] Pinned `source = "...//ref=vX.Y.Z"`, not `main`

**Operational**
- [ ] CloudWatch log group with explicit retention (not "Never expire")
- [ ] Alarms for failure modes (DLQ depth, error rate, throttles)
- [ ] Backup/PITR for stateful resources

Report grouped by severity (Blocker / High / Medium / Nit) with file:line,
the concern in one sentence, and the recommended change in one sentence.
End with: `VERDICT: <approve | request-changes | block>` and a one-line why.
