# Skills

This directory contains the skill catalog. Each skill is a self-contained directory with a `SKILL.md` (frontmatter + body), and optional `assets/`, `references/`, `scripts/`, and `agents/` subdirectories.

This README is the index: what each skill does and when to reach for it. For the authoritative description and trigger criteria, read the `SKILL.md` inside the skill itself.

---

## skill-creator

**What it does.** Scaffolds new skills, edits and improves existing ones, runs evals against a skill, and tunes a skill's description for better triggering accuracy. Includes scripts for benchmarking with variance analysis and generating review pages.

**When to use.** Creating a skill from scratch, restructuring or rewriting an existing skill, running quantitative evals on a skill, or optimizing a skill's description so it triggers on the right prompts (and not the wrong ones).

---

## aws-solution-architect

**What it does.** Guides AWS architecture decisions — service selection, multi-account strategy, sizing for scale and cost, network topology, security/identity, resilience patterns, and Architecture Decision Records — framed around the Well-Architected Framework pillars.

**When to use.** Designing a new system on AWS, choosing between AWS services for the same job, reviewing an existing architecture for risk/cost/scaling concerns, writing or reviewing an ADR, or planning a scaling decision (sharding, multi-region, multi-account split).

---

## gitlab-pipeline

**What it does.** Covers production GitLab CI/CD design on GitLab 17+ — `.gitlab-ci.yml` structure, `workflow:`/`rules:`, includes and templates, caching and artifacts, parallel and DAG jobs, environments, OIDC auth to AWS, multi-account deploys, secrets handling, and review apps.

**When to use.** Designing a new pipeline from scratch, refactoring a pipeline that is slow/flaky/hard to read, adding cloud deploys without static credentials, or fixing duplicate-MR pipelines and cache misses.

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

## Adding a new skill

Use `skill-creator`. The catalog conventions are:

- `SKILL.md` at the skill root with `name` and `description` frontmatter
- `assets/` for templated files the skill emits to the user's project (not `templates/`)
- `references/` for deep-dive material the skill loads on demand
- `scripts/` for executable helpers
- `agents/` for sub-agent definitions, if the skill spawns any
- Register the skill in `scripts/manifest.txt`
