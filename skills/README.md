# Skills

This directory contains the skill catalog. Each skill is a self-contained directory with a `SKILL.md` (frontmatter + body), and optional `assets/`, `references/`, `scripts/`, and `agents/` subdirectories.

This README is the index: what each skill does and when to reach for it. For the authoritative description and trigger criteria, read the `SKILL.md` inside the skill itself.

---

## skill-creator

**What it does.** Scaffolds new skills, edits and improves existing ones, runs evals against a skill, and tunes a skill's description for better triggering accuracy. Includes scripts for benchmarking with variance analysis and generating review pages.

**When to use.** Creating a skill from scratch, restructuring or rewriting an existing skill, running quantitative evals on a skill, or optimizing a skill's description so it triggers on the right prompts (and not the wrong ones).

---

## superpowers

**What it does.** A disciplined software-development workflow ported from [obra/superpowers](https://github.com/obra/superpowers) (MIT) and adapted for kiro: brainstorm → git worktree → write plan → execute (subagent-driven or inline) → test-driven development → code review → finish the branch, plus systematic-debugging and verification-before-completion. The `SKILL.md` is the router; each stage is a reference file under `references/`. A companion steering file (`steering/superpowers-tools.md`, installed alongside) carries the Claude Code → kiro **tool-mapping table** so the original tool names (`Read`/`Edit`/`Bash`/`Task`/`Skill`) translate to kiro verbs (`fs_read`/`fs_write`/`execute_bash`/`subagent`).

**When to use.** Starting any non-trivial build/fix/refactor where process matters — you want the agent to refine and plan before coding, drive each change test-first, review against the plan, and close the branch deliberately. Skip for throwaway prototypes or pure config edits. To author *new* kiro skills, use `skill-creator` rather than this bundle.

---

## automation-solutions

**What it does.** Playbook for running kiro-cli headlessly — git hooks (pre-commit review, commit-message draft/validate, post-commit doc sync, pre-push security scan) and scheduled jobs (nightly pipeline triage, dependency CVE scan, weekly steering refresh). Ships runnable scripts, a `.githooks/` installer, and the read-only agents each workflow invokes. Every invocation is read-only; anything that would change a file is proposed as a unified diff.

**When to use.** Wiring kiro into git hooks or cron/systemd timers, deciding where an expensive check should live (pre-commit vs. pre-push vs. cron), or hardening/debugging existing kiro automation (fail-open, skip switches, cost, key handling).

---

## aws-solution-architect

**What it does.** Guides AWS architecture decisions — service selection, multi-account strategy, sizing for scale and cost, network topology, security/identity, resilience patterns, and Architecture Decision Records — framed around the Well-Architected Framework pillars.

**When to use.** Designing a new system on AWS, choosing between AWS services for the same job, reviewing an existing architecture for risk/cost/scaling concerns, writing or reviewing an ADR, or planning a scaling decision (sharding, multi-region, multi-account split).

---

## gitlab-duo-review

**What it does.** Configures GitLab Duo Code Review (the non-agentic reviewer) for a project by producing a tailored `.gitlab/duo/mr-review-instructions.yaml`. Works review-then-author: inventory the repo's languages, layout, and conventions (a `detect-stack.sh` helper seeds `fileFilters` globs), harvest the real review nits, then write scoped, per-area instruction groups phrased as hints. Ships an annotated starter template, stack-specific example groups (Python/Lambda, Terraform/Terragrunt, GitLab CI, Kubernetes, TypeScript, a security baseline), a validator that lints schema/globs/mandate-phrasing, and references for the YAML schema, glob syntax, group/instance-level templates, and the reviewer's guidance-not-policy limits.

**When to use.** Standing up Duo custom review instructions on a repo for the first time, capturing repeated manual review comments as Duo hints, scoping different guidance per language/area in a monorepo, setting a shared group/instance-level baseline, or auditing an existing instructions file that has grown noisy or full of "always/never" mandates. Skip for enforceable gates (use `gitlab-pipeline` CI quality gates) and for the *agentic* Code Review Flow.

---

## gitlab-pipeline

**What it does.** Covers production GitLab CI/CD design on GitLab 17+ — `.gitlab-ci.yml` structure, `workflow:`/`rules:`, includes and templates, caching and artifacts, parallel and DAG jobs, environments, OIDC auth to AWS, multi-account deploys, secrets handling, and review apps.

**When to use.** Designing a new pipeline from scratch, refactoring a pipeline that is slow/flaky/hard to read, adding cloud deploys without static credentials, or fixing duplicate-MR pipelines and cache misses.

---

## kubernetes-eks

**What it does.** Production Kubernetes on Amazon EKS — workload manifest design (resource limits, probes, securityContext, topology spread, PodDisruptionBudgets), IRSA for AWS access, NetworkPolicy and Pod Security Admission, RBAC scoping, Helm/Kustomize and GitOps delivery, and a read-only triage playbook (CrashLoop/ImagePull/Pending/OOMKilled/node pressure with an exit-code decoder). Ships a GET-only `triage.sh` snapshot script.

**When to use.** Writing or reviewing a Deployment/Helm chart/Kustomize overlay for EKS, wiring a pod to AWS via IRSA, hardening workloads, or debugging a failing pod/node. The IaC that provisions the cluster lives in `terraform-aws` / `terragrunt-multi-account`; broader topology decisions live in `aws-solution-architect`. The `eks-troubleshooter` agent loads this skill.

---

## python-devops-aws

**What it does.** Production-grade Python patterns for AWS automation outside Lambda — boto3 client/resource use, credential resolution, assume-role, retries and pagination, error handling, structured logging, packaging, and testing.

**When to use.** Writing a script or CLI that calls AWS APIs from a CI runner, EC2/ECS, or a laptop; automating IAM/S3/EC2/RDS; building safe, re-runnable remediation scripts; or distributing shared AWS tooling to multiple engineers.

---

## python-lambda

**What it does.** Lambda-specific Python patterns — handler structure, module-scope vs handler-scope, cold start optimization, AWS Lambda Powertools, Parameter Store / Secrets Manager access, environment variables, error handling and DLQs, zip vs layer vs container packaging, and local testing. Assumes the boto3 conventions in `python-devops-aws`.

**When to use.** Writing a new Python Lambda handler, modifying an existing handler (new event source, response shape, retries), debugging cold start / timeout / memory issues, wiring an event source (S3, SQS, SNS, EventBridge, Kinesis, DynamoDB Streams, API Gateway), or choosing a packaging strategy.

---

## security-code-reviewer

**What it does.** Hypothesis-driven security review of code, IaC, and CI/CD config. Covers injection, SSRF, deserialization, auth/session, IDOR, XSS, CSRF, TOCTOU, secrets handling, AWS-specific code review, container and IaC review, and dependency review. Output is a structured report with severity, evidence, reproduction, and a concrete fix per finding.

**When to use.** Reviewing a PR for security issues after SAST/SCA/secret-scanners have run; auditing IaC or CI configs for IAM over-permission, secret exposure, or authorization bypass; or investigating business-logic flaws automated tooling misses.

---

## steampipe

**What it does.** Querying cloud APIs as Postgres tables for inventory, audit, compliance, and cost analysis — plugin setup, multi-account/multi-region AWS aggregator connections, query patterns, JSONB column handling, Powerpipe benchmarks (CIS, NIST, AWS FSBP, PCI, HIPAA), Flowpipe pipelines, and CI integration. Assumes the audit-role layout from `terragrunt-multi-account`.

**When to use.** Building a cross-account AWS inventory or audit query, running compliance benchmarks against an estate, exploring cloud state with SQL, or wiring query results into automated workflows.

---

## powerpipe-reporting

**What it does.** The reporting/visualization layer on top of Steampipe — authoring Powerpipe **mods** (dashboards, benchmarks, controls in HCL), running the same report across multiple AWS environments via a Steampipe aggregator and `--search-path-prefix`, producing artifacts (HTML, snapshots, ASFF→Security Hub, JSON gates), and AWS **cost** reporting through the AWS Pricing (free, estimates) and Cost Explorer ($0.01/call, actuals) MCP servers. Ships a starter `mod.pp`, two dashboards, a custom baseline benchmark, a scheduled GitLab CI job, and run/install scripts.

**When to use.** Turning ad-hoc `steampipe query` one-offs into a repeatable per-environment report, authoring dashboards/benchmarks, diffing posture across dev/staging/prod, or reporting per-environment spend and turning idle resources into a $/month savings figure. The query/connection layer underneath lives in `steampipe`.

---

## terraform-aws

**What it does.** Production Terraform on AWS — project structure, remote state on S3 + DynamoDB, module design, provider configuration, AWS-specific patterns (IAM, VPC, KMS), variable validation, lifecycle and meta-arguments, drift management, and testing with `terraform validate`, tflint, checkov, and terratest.

**When to use.** Writing a new Terraform module or root config for AWS, reviewing a Terraform PR, debugging drift / plan churn / surprise replacements, designing a fresh Terraform repo layout, or migrating local state to a remote backend.

---

## terragrunt-multi-account

**What it does.** Terragrunt as a multi-account / multi-environment orchestrator on top of Terraform — root vs child `terragrunt.hcl`, generated backend and provider blocks, includes and unit hierarchies, dependency management, `run-all` safety, account/environment directory layout, and migration from raw Terraform. Orchestration layer only — module design lives in `terraform-aws`.

**When to use.** Standing up a multi-account AWS landing zone with many stacks, removing backend/provider duplication across environments, ordering dependent applies across stacks, or migrating an existing raw-Terraform estate onto Terragrunt.

---

## Cross-references

Several skills assume context from others. Common chains:

- `python-lambda` → `python-devops-aws` (boto3 / retry / pagination conventions)
- `steampipe` → `terragrunt-multi-account` (audit-role layout) → `aws-solution-architect` (topology)
- `security-code-reviewer` ← `steampipe` (findings feed in)
- `terragrunt-multi-account` → `terraform-aws` (module / HCL primitives) → `aws-solution-architect` (service selection)
- `kubernetes-eks` → `terraform-aws` / `terragrunt-multi-account` (cluster + IRSA IaC) → `aws-solution-architect` (topology); `security-code-reviewer` (manifest review)
- `automation-solutions` → `security-code-reviewer` (the agents it runs in hooks) + `gitlab-pipeline` (pipeline-troubleshooter context)
- `gitlab-duo-review` → `gitlab-pipeline` (enforceable CI gates that hints must not replace) + `security-code-reviewer` (repeatable low-severity checks that make good Duo hints)
- `powerpipe-reporting` → `steampipe` (query/connection layer) → `terragrunt-multi-account` (audit-role layout) + `gitlab-pipeline` (CI publish job)

## Adding a new skill

Use `skill-creator`. The catalog conventions are:

- `SKILL.md` at the skill root with `name` and `description` frontmatter
- `assets/` for templated files the skill emits to the user's project (not `templates/`)
- `references/` for deep-dive material the skill loads on demand
- `scripts/` for executable helpers
- `agents/` for sub-agent definitions, if the skill spawns any
- Register the skill in `scripts/manifest.txt`
