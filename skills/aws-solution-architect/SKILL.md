---
name: aws-solution-architect
description: Use when designing AWS architectures, choosing between services, planning multi-account strategy, sizing for scale and cost, or producing an architecture decision record — covers the Well-Architected Framework pillars, compute/storage/data selection, networking topology, security and identity, resilience patterns, and cost optimization
---

# AWS Solution Architecture

## Overview

Architecture is decision-making under constraint. Most AWS architectures are not novel — they are five high-leverage decisions made well, surrounded by well-known patterns. Get the high-leverage decisions right, record them as ADRs, and the rest follows from convention.

The mindset: design for 10x growth in scope, traffic, and team size. Premature scale is waste, but unrecoverable architectural choices (single account, public RDS, baked-in IAM users) are far more expensive to undo than they were to prevent.

## When to Use

- Designing a new system on AWS from a blank slate
- Choosing between two or more AWS services for the same job
- Reviewing an existing architecture for risk, cost, or scaling concerns
- Writing or reviewing an Architecture Decision Record (ADR)
- Planning a scaling decision (sharding, multi-region, multi-account split)
- Doing a cost review and looking for structural — not tactical — savings
- Onboarding a team to AWS and needing a defensible default landing zone
- Migrating from on-prem, another cloud, or a single-account "we'll fix it later" setup

Do not use this skill for line-by-line Terraform, CloudFormation syntax, or runtime debugging — defer to `terraform-aws`, `terragrunt-multi-account`, or service-specific skills.

## The 5 High-Leverage Decisions

These five decisions determine almost everything else. Get them explicit and recorded; the rest follows from convention.

| # | Decision | Reference |
|---|---|---|
| 1 | **Account topology** — single vs multi-account, OUs, splitting axes, SCP guardrails | `references/account-topology.md` |
| 2 | **Network topology** — VPC sizing, TGW vs peering, NAT, VPC endpoints, hybrid | `references/networking.md` |
| 3 | **Identity model** — IAM Identity Center for humans, roles + OIDC/IRSA for machines | `references/identity.md` |
| 4 | **Primary compute** — Lambda, Fargate, ECS, EKS, EC2, App Runner, Batch | `references/compute-selection.md` |
| 5 | **Primary data store** — RDS, Aurora, DynamoDB, OpenSearch, Redshift, S3+Athena | `references/data-selection.md` |

Everything else — observability, CI/CD, secrets management, edge — flows from those five. An architect's job is to make those decisions explicit, defensible, and recorded as ADRs.

## Well-Architected Framework

The WAF has six pillars. An architect treats them as question sets used during design, not as a checkbox audit. One line per pillar; full question sets in `references/well-architected.md`.

| Pillar | What it asks |
|---|---|
| Operational Excellence | Can the team detect, deploy, roll back, and learn from incidents? |
| Security | What is the blast radius, and how is it contained? |
| Reliability | Does the architecture meet stated RTO/RPO under tested failure? |
| Performance Efficiency | Are access patterns and SLOs the inputs to the design? |
| Cost Optimization | Are the structural cost levers (savings plans, Graviton, NAT, tags) pulled? |
| Sustainability | Are idle and oversize resources hunted continuously? |

A WAF review is not done until each pillar has documented answers. The output is a list of accepted risks plus a backlog of remediations.

## Templates

| Template | Purpose |
|---|---|
| `assets/adr.md` | Architecture Decision Record — Context / Decision / Alternatives / Consequences / References, with a worked Aurora Serverless v2 example at the end |
| `assets/design-doc.md` | One-page system design doc — problem, constraints, proposed architecture, risks, open questions, cost estimate |
| `assets/architecture-review-checklist.md` | WAF-driven review checklist organized by the six pillars — ~50 items |
| `assets/threat-model-worksheet.md` | STRIDE-lite worksheet — per-component spoofing/tampering/repudiation/info-disclosure/DoS/EoP analysis |

## References

| Reference | Covers |
|---|---|
| `references/well-architected.md` | The six pillars as actionable question sets |
| `references/account-topology.md` | AWS Organizations, Control Tower, OUs, multi-account splitting criteria, SCPs |
| `references/networking.md` | VPC sizing, TGW vs peering, NAT GW, endpoints, PrivateLink, hybrid |
| `references/identity.md` | IAM Identity Center, permission sets, machine identity (IRSA, OIDC, Roles Anywhere) |
| `references/compute-selection.md` | Lambda/Fargate/ECS/EKS/EC2/App Runner/Batch decision matrix |
| `references/data-selection.md` | RDS/Aurora/DynamoDB/OpenSearch/Redshift/S3+Athena/Timestream/Neptune decision matrix |
| `references/resilience.md` | Multi-AZ/region patterns, RTO/RPO, DR strategies, recovery testing |
| `references/security-baseline.md` | CloudTrail/GuardDuty/Config/SCPs/KMS non-negotiables |
| `references/cost-optimization.md` | Savings Plans, Graviton, Spot, S3 classes, NAT trap, tagging |
| `references/reference-architectures.md` | Public web, event-driven, data lake, landing zone sketches |

## Common Mistakes

| Mistake | Why it bites | Fix |
|---|---|---|
| Single-account architecture for anything beyond a side project | No blast-radius isolation, IAM tangle, billing opaque | Multi-account from day one |
| Public RDS / public managed DBs | One leaked sg rule from data exfiltration | RDS in isolated subnets, no public IP |
| Lambda for sustained high-throughput compute | Cost crosses Fargate around steady ~50% utilization | Move sustained load to Fargate |
| DynamoDB chosen for relational queries | Forces app-side joins, painful migrations | Use Postgres for relational data |
| No multi-AZ on RDS in prod | One AZ event = full outage | Multi-AZ default |
| No CloudTrail / GuardDuty | Forensic blind spot, undetected compromise | Enable org-wide from day one |
| "We'll add monitoring later" | Outages debugged via SSH and `tail -f` | Observability is part of the MVP, not a v2 task |
| No tagging strategy | No cost visibility, no chargeback | Mandatory tags via SCP from day one |
| VPC peering at scale (>5 VPCs) | N² mesh, brittle routing | Transit Gateway |
| Cross-region without measuring whether it's needed | 2x cost, complex failover, often unused | Multi-AZ first, multi-region when RTO/regulation demands |
| Long-lived IAM access keys | Leaked keys are the #1 AWS breach vector | OIDC for CI, IAM roles for compute, Identity Center for humans |
| `0.0.0.0/0` ingress on instance SGs | Direct internet exposure of compute | Edge via ALB/CloudFront/NLB only |
| Single NAT GW serving multiple VPCs without VPC endpoints | Five-figure NAT processing bills | Gateway endpoints for S3/DynamoDB, interface endpoints for noisy services |

## Quick Reference

For the at-a-glance decision tables — compute, data store, networking, identity — go directly to the matrix at the bottom of `references/compute-selection.md` and `references/data-selection.md`. Networking and identity quick tables live at the bottom of `references/networking.md` and `references/identity.md`.

## Cross-References

- **Implementation.** This skill produces design inputs; the `terraform-aws` skill (module patterns, provider config, state) and `terragrunt-multi-account` skill (DRY config across accounts and regions, account vending, remote state per account) turn them into running infrastructure.
- **Code-level security audit.** The architectural baseline in `references/security-baseline.md` is the floor. For code-level vulnerability review (IAM policy analysis, secret scanning, dependency CVEs), use the `security-code-reviewer` skill.
