---
name: gitlab-pipeline
description: Use when designing or implementing GitLab CI/CD pipelines — covers .gitlab-ci.yml structure, rules and workflow, includes/templates, caching and artifacts, parallel and DAG jobs, environments, OIDC auth to AWS, multi-account deploys, secrets handling, and review apps
---

# GitLab CI/CD Pipeline Design

## Overview

A production GitLab pipeline must be declarative, fast, deterministic,
and observable. The two parts that go wrong most often in real
codebases are caching (wrong keys, wrong policy, wrong place) and rules
(missing `workflow:rules:`, deprecated `only/except`, duplicate-MR
pipelines). The patterns in this skill assume GitLab 17+ syntax.

## When to Use

- Designing a new pipeline from scratch and choosing the file layout.
- Refactoring an existing pipeline that is slow, flaky, or hard to read.
- Adding deploys to AWS, GCP, or Azure and removing static cloud
  credentials from CI variables.
- Sharing CI patterns across many repos via includes or CI/CD Components.
- Adding review apps, multi-environment promotion, or manual prod gates.
- Diagnosing duplicate-pipeline issues on merge requests.

Skip for application-level concerns (build script logic, test authoring)
and use the language-specific skills instead.

## The pipeline shape

The root `.gitlab-ci.yml` is thin: it declares stages, the `default:`
block, the `workflow:rules:` gate, and `include:`s component files.
Each job is an `extends` of a hidden template (e.g. `.aws-auth`,
`.base_node`). DAG ordering is via `needs:`. Cloud auth is via OIDC
with `id_tokens:` and `assume-role-with-web-identity` — never CI
variables for AWS keys. Anything beyond ~150 lines of root file is a
refactor signal: split into `.gitlab/ci/*.yml` includes or pin a CI/CD
Component by tag.

## Templates

| File | Purpose |
|---|---|
| `assets/.gitlab-ci.yml` | Thin root with `workflow:rules`, `default:`, stages, three `include:` shapes. |
| `assets/aws-oidc.yml` | `.aws-auth` hidden job using `id_tokens` and `sts assume-role-with-web-identity`. |
| `assets/terraform-deploy.yml` | `validate`/`plan`/`apply` stages with MR-vs-default-vs-tag rules, manual prod gate, `resource_group` serialisation, MR-comment plan. |
| `assets/review-app.yml` | Dynamic environment per branch with `on_stop` and `auto_stop_in`. |
| `assets/aws-trust-policy.json` | IAM trust policy assumable by GitLab OIDC, with `sub`-claim conditions for branch and environment. |

## References

| File | Topic |
|---|---|
| `references/rules-and-workflow.md` | `rules:`, `workflow:rules:`, the duplicate-MR-pipeline trap, predefined CI variables. |
| `references/cache-vs-artifacts.md` | Caching policy and keys, `artifacts:reports:*`, common per-language patterns. |
| `references/oidc-cloud-auth.md` | OIDC to AWS, GCP, and Azure with `id_tokens`; Vault integration; secret hygiene. |
| `references/multi-environment.md` | `environment:`, review apps, `resource_group`, multi-account deploys. |
| `references/quality-gates.md` | SAST/SCA/secret-detection templates, coverage regexes, retry/interruptible/parallel. |

## Scripts

| File | Purpose |
|---|---|
| `scripts/detect-changed-modules.sh` | Compute changed Terragrunt modules vs the MR merge-base; emit space-separated paths for `--terragrunt-include-dir`. |

## Cross-references

- `terragrunt-multi-account` — Terragrunt-side layout that mirrors the
  AWS account boundary referenced in `multi-environment.md`.
- `terraform-aws` — IaC for the OIDC provider, IAM roles, and trust
  policies consumed by `aws-oidc.yml` and `aws-trust-policy.json`.

## Common Mistakes

| Mistake | Fix |
|---|---|
| `only/except` in a new pipeline | Use `rules:` |
| AWS keys stored as masked CI variables | OIDC + `assume-role-with-web-identity` |
| Caching build outputs | Move to `artifacts:` |
| No `workflow:rules:`, duplicate MR pipelines | Add the canonical workflow rules block |
| Global `image:` for the whole pipeline | Set `image:` per job (or in `default:`) |
| Long-running test jobs not `interruptible:` | Add `interruptible: true` outside deploy stage |
| `retry: 2` masking flaky tests | Constrain `retry.when` to infra failures |
| One 800-line `.gitlab-ci.yml` | Split into `.gitlab/ci/*.yml` includes |
| Manual prod deploy without `resource_group:` | Add `resource_group: production` |
| `echo $SECRET` for debugging | Remove; secrets belong in tools, not logs |
| MR pipeline running on docs-only changes | `workflow:rules:` with `if: $CI_COMMIT_TITLE =~ /^docs:/ when: never` |
| Pinning `include: project` to `main` | Pin to a tag (`ref: v3.2.0`) |
| Static `AWS_ROLE_ARN` per job | Scope to GitLab environment, drive via `CI_ENVIRONMENT_NAME` |
| YAML `<<: *anchor` losing nested keys | Use `extends:` (deep merge) |

## Quick Reference

| Keyword | Purpose |
|---|---|
| `stages:` | Ordered pipeline phases |
| `needs:` | DAG ordering, overrides stage waits |
| `rules:` | Per-job conditional execution |
| `workflow:rules:` | Whether to create the pipeline at all |
| `extends:` | Deep-merge inheritance from a hidden base job |
| `include:` | Pull YAML from local, project, remote, template, or component |
| `cache:` | Speed up future jobs (deps), keyed |
| `artifacts:` | Pass build outputs downstream, expires |
| `id_tokens:` | Mint a GitLab JWT for OIDC |
| `secrets:` | Inject from external vault |
| `environment:` | Track deploys, drive OIDC sub claim |
| `resource_group:` | Serialise jobs sharing a name |
| `interruptible:` | Cancel on newer pipeline |
| `retry:` | Re-run on listed failure classes |
| `parallel:matrix:` | Fan out a job over variable combinations |
| `image:` / `services:` | Container image and sidecars |
| `tags:` | Select runner pool |
| `when:` | `on_success`/`manual`/`always`/`never`/`delayed` |
| `allow_failure:` | Don't fail the pipeline if this job fails |
| `coverage:` | Regex to extract coverage % from logs |
| `artifacts:reports:junit` | Surface test results in MR UI |
| `artifacts:reports:dotenv` | Export variables to downstream jobs |
| `CI_PIPELINE_SOURCE` | `push`, `merge_request_event`, `schedule`, `web`, `api` |
| `CI_ENVIRONMENT_NAME` | Resolved environment name in deploy jobs |
| `CI_COMMIT_REF_SLUG` | URL-safe ref name, useful in cache keys |
