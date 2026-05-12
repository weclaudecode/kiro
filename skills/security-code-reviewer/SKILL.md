---
name: security-code-reviewer
description: Use when reviewing code, infrastructure-as-code, or CI/CD configurations for security vulnerabilities — covers application flaw classes (injection, SSRF, deserialization, auth/session, IDOR, XSS, CSRF, TOCTOU, secrets), AWS-specific code review, IaC and container review, and dependency review
---

# Security Code Review

## Overview

Security review is hypothesis-driven, not checklist-driven. The reviewer
imagines the attacker, finds the trust boundaries, and checks whether the
code holds at each one. The deliverable is a structured report with severity,
evidence, reproduction, and a concrete fix for every finding — never a
free-form list of worries.

This skill complements automated tooling. It does not replace SAST (semgrep,
CodeQL, bandit), SCA (snyk, dependabot, pip-audit), secret scanners (gitleaks,
trufflehog), or IaC scanners (checkov, tfsec, trivy config). Run those first,
then use human review to find what they miss: business-logic flaws, IAM
over-permission, secrets in unusual places, TOCTOU races, authorization bypass,
and broken multi-tenant isolation.

## When to Use

- Pull-request review touching auth, payments, file I/O, external HTTP, or any
  new HTTP/queue handler
- Pre-prod audit before a service moves from staging to production or before
  exposing an internal service to the public internet
- Post-incident review — find related weaknesses before attackers do
- Periodic repo audit (quarterly or yearly) of a long-lived service
- Major framework upgrade (Django 3 to 5, Spring Boot 2 to 3) where security
  defaults may have changed

Do not use this skill when an automated tool can answer the question, when
the codebase has never been scanned (run SAST/SCA first), or when the change
is documentation- or test-only with no production code path.

## Methodology

The review proceeds in five phases. The reviewer ticks through
`assets/review-checklist.md` while doing this.

1. **Scope** — write a two-line threat model: public or internal, PII or
   payments, multi-tenant, language and runtime, in-scope artifacts (diff vs.
   whole repo vs. IaC and CI).
2. **Map trust boundaries** — list every place untrusted input crosses into
   trusted code (HTTP handlers, queue consumers, file uploads, deserializers,
   webhooks, env vars sourced from less-trusted layers).
3. **Walk each boundary** — trace input forward to its sink. Check each
   boundary against the relevant flaw classes in
   `references/flaw-classes.md`. Use cloud-specific patterns from
   `references/aws-code-review.md` where applicable.
4. **Out-of-band checks** — secrets in git history, dependency CVEs, IaC and
   container misconfigurations, CI/CD pipeline trust. See
   `references/iac-and-containers.md`, `references/cicd-review.md`,
   `references/dependency-review.md`.
5. **Write findings** — one finding per issue using
   `assets/finding-report.md`, severity assigned via
   `assets/severity-rubric.md`. Group only when findings share a single
   root cause and a single fix.

## Findings Report — Required Fields

Every finding must include:

- **Title** — short, specific (e.g. "SQL injection in
  `OrderRepository.findByUser`", not "SQL issue").
- **Severity** — Critical / High / Medium / Low / Informational, assigned
  using `assets/severity-rubric.md`.
- **CWE/OWASP reference** — e.g. `CWE-89 (SQL Injection)`,
  `OWASP A03:2021`.
- **Location** — `path/to/file.py:42-48`, with the actual vulnerable code as
  a snippet.
- **Impact** — what an attacker can do, concretely. Name the data, the path,
  the payload, the rows or accounts affected. Never "may lead to data
  exposure".
- **Reproduction** — a `curl` command, a payload, or a test snippet that
  demonstrates the issue.
- **Remediation** — the fix, with a corrected code snippet. Address the root
  cause, not the symptom.
- **References** — CWE link, CVE if applicable, vendor advisory, OWASP
  cheat sheet.

The full layout, with placeholders and a worked example, is in
`assets/finding-report.md`.

## Templates

| Template | Purpose |
| --- | --- |
| `assets/finding-report.md` | Layout for a single finding, with placeholders and a worked example |
| `assets/severity-rubric.md` | One-page rubric: criteria for Critical / High / Medium / Low / Informational |
| `assets/review-checklist.md` | ~50-item checklist organized by phase 1-5 for the reviewer to tick through |

## References

| Reference | Covers |
| --- | --- |
| `references/methodology.md` | Detailed walk-through of the five phases |
| `references/flaw-classes.md` | Injection (SQL, NoSQL, command, template), SSRF, deserialization, auth/session, authorization (IDOR), XSS, CSRF, TOCTOU, secrets — vulnerable and fixed code in Python, JS/TS, Java, Go where patterns differ |
| `references/aws-code-review.md` | boto3 and AWS SDK call patterns: bucket scoping, presigned URLs, KMS context, cross-account `assume_role`, Lambda env secrets |
| `references/iac-and-containers.md` | Terraform / CloudFormation / CDK findings; Dockerfile review (root user, build secrets, base-image pinning, SBOM) |
| `references/cicd-review.md` | Pipeline as attack surface: untrusted PR runs, `pull_request_target`, OIDC trust policies, action pinning, runner isolation |
| `references/dependency-review.md` | Lockfiles, SBOM, transitive CVEs, typosquats, abandoned packages |

## Quick Scan

Before starting manual review, run automated scanners (semgrep, gitleaks,
checkov, trivy, the language SCA tool). Then run
`scripts/grep-patterns.sh` for a fast pass over common antipatterns —
`pickle.loads`, `yaml.load`, `eval`, `subprocess(... shell=True)`, weak hash
algorithms, hardcoded AWS keys, `alg: none` JWT, etc. The script's output
is a starting point for the boundary walk, not a substitute for it.

## Common Mistakes by Reviewers

| Mistake | Why it is wrong | What to do instead |
| --- | --- | --- |
| Stopping at the first finding | One bug rarely lives alone; the same coding pattern often repeats | Complete the walk of every boundary before writing up |
| Marking everything Critical | Inflation makes the team ignore real Criticals | Apply the rubric. Reserve Critical for unauth RCE / full breach |
| Vague descriptions ("could lead to issues") | Developer cannot act on it | Name the data, the path, the payload, the impact |
| Recommending a band-aid | Escaping one input still leaves the next call vulnerable | Fix the root cause: parameterize the query, allowlist the URL |
| Not verifying the finding | Reports false positives erode trust | Reproduce with curl/payload/test before filing |
| Trusting "this is internal-only" | Internal services get exposed by misconfig, lateral movement, SSRF | Threat-model with a compromised-insider assumption |
| Ignoring IaC and CI | Most modern breaches go through cloud config or pipeline | Always include `.github/`, `terraform/`, `Dockerfile` in scope |
| Reviewing only the diff | Diff-only review misses pre-existing flaws the diff exposes more deeply | Read the call sites of changed functions; expand scope when warranted |
| Reporting findings without a fix | Leaves the team to research the fix under time pressure | Provide the corrected code snippet |
