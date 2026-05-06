---
name: aws-solution-architect
description: Use when designing AWS architectures, choosing between services, planning multi-account strategy, sizing for scale and cost, or producing an architecture decision record — covers the Well-Architected Framework pillars, compute/storage/data selection, networking topology, security and identity, resilience patterns, and cost optimization
---

# AWS Solution Architecture

## Overview

Architecture is decision-making under constraint. Most AWS architectures are not novel — they are 5 to 10 high-leverage decisions made well, surrounded by well-known patterns. Get the high-leverage decisions right and the rest follows from convention.

The five decisions that determine almost everything else:

1. **Account topology** — single account or multi-account, and what splits the accounts
2. **Network topology** — VPC layout, egress shape, cross-account connectivity
3. **Identity model** — how humans and machines authenticate and authorize
4. **Primary compute** — Lambda, Fargate, ECS, EKS, EC2, App Runner, Batch
5. **Primary data store** — RDS, Aurora, DynamoDB, Aurora Serverless v2, OpenSearch, S3 + Athena

Everything else — observability, CI/CD, secrets management, edge — flows from those five. An SA's job is to make those decisions explicit, defensible, and recorded as ADRs. Implementation lives in the `terraform-aws` and `terragrunt-multi-account` skills; this skill covers the design layer that produces the inputs to those.

The mindset: design for 10x growth in scope, traffic, and team size. Premature scale is waste, but unrecoverable architectural choices (single account, public RDS, baked-in IAM users) are far more expensive to undo than they were to prevent.

## When to Use

Use this skill when:

- Designing a new system on AWS from a blank slate
- Choosing between two or more AWS services for the same job
- Reviewing an existing architecture for risk, cost, or scaling concerns
- Writing or reviewing an Architecture Decision Record (ADR)
- Planning a scaling decision (sharding, multi-region, multi-account split)
- Doing a cost review and looking for structural — not tactical — savings
- Onboarding a team to AWS and needing a defensible default landing zone
- Migrating from on-prem, another cloud, or a single-account "we'll fix it later" setup

Do not use this skill for line-by-line Terraform, CloudFormation syntax, or runtime debugging — defer to `terraform-aws`, `terragrunt-multi-account`, or service-specific skills.

## Well-Architected Framework — what to actually do with it

The Well-Architected Framework (WAF) has six pillars. Most teams treat it as a checkbox audit; an SA treats it as a question set used during design. For each pillar, ask the questions below before the design is frozen.

### Operational Excellence

- How do operators discover that something is broken — alerts, dashboards, customer reports? What is the mean time to detection target?
- How is configuration managed — IaC end-to-end, or are there click-ops corners? Where are the gaps?
- How are runbooks kept current? Who runs game-days?
- What is the deploy cadence and rollback time? Can the team deploy on a Friday afternoon?
- Are post-incident reviews blameless and do they produce concrete action items?

### Security

- What is the blast radius of a compromised IAM principal in the worst-case account?
- Is data encrypted in transit and at rest by default? Where is it not, and why?
- How would a privileged credential leak be detected and rotated within an hour?
- Are there `0.0.0.0/0` ingress rules? On what, and is there a WAF in front?
- Is CloudTrail organization-wide, immutable, and centralized? Is GuardDuty on in every account and region in use?

### Reliability

- What is the RTO and RPO for each tier of service, and is the architecture actually capable of meeting them?
- What happens when a single AZ fails? A region? A dependency?
- Are failures tested — chaos days, fail-over rehearsals — or only theoretical?
- Are there hard quotas (Lambda concurrency, RDS connections, ENI limits) that throttle the system before infrastructure does?
- Is there backpressure on every queue and async boundary?

### Performance Efficiency

- Has the access pattern been characterized before the data store was chosen, or was it the other way round?
- Where are the latency SLOs and how are they measured (p50, p95, p99)?
- Is compute right-sized? Is Graviton (ARM) on the table?
- Is caching present where it would actually help (CloudFront, ElastiCache, DAX), or is it cargo-culted?
- Are there hot keys, hot partitions, or hot shards lurking?

### Cost Optimization

- Is there a tagging strategy enforced via SCP and used by Cost Explorer?
- Are Compute Savings Plans applied where utilization is steady?
- Where is NAT Gateway processing data that should be going through a VPC endpoint?
- Are non-prod environments shutting down outside business hours?
- Is S3 Intelligent-Tiering on by default for unknown access patterns?

### Sustainability

- Is the workload region chosen with carbon intensity in mind where it does not violate latency or compliance?
- Are idle resources hunted regularly (orphaned EBS, unused EIPs, dev environments left on)?
- Is right-sizing continuous, or a one-time exercise?
- Are managed services preferred over self-managed where they shift utilization to AWS's shared fleet?

A WAF review is not done until each pillar has documented answers. The output is a list of accepted risks plus a backlog of remediations, not a passing grade.

## The 5 high-leverage decisions

### 1. Account topology

Default to multi-account from day one. A single account is acceptable only for individual side projects and disposable demos. Multi-account is non-negotiable for anything with production data, multiple environments, or more than one team.

**Why multi-account.** Account is the strongest blast-radius boundary AWS offers — stronger than VPC, IAM policy, or SCP. It contains IAM, quotas, billing, and most service limits. Splitting by account makes "compromise in dev cannot reach prod" structural, not policy-based.

**Foundation: AWS Organizations + Control Tower + IAM Identity Center.** Control Tower provides a managed landing zone — an Organization, mandatory accounts (management, log archive, audit), guardrails (SCPs and Config rules), and Account Factory for vending. IAM Identity Center (formerly AWS SSO) is the single identity plane for humans across all accounts.

**OU design — start here:**

| OU | Purpose |
|---|---|
| `Security` | Log archive account, audit/security tooling account |
| `Infrastructure` | Shared services — networking hub, central CI/CD, shared DNS |
| `Workloads/Prod` | Production workload accounts, one per app or per team |
| `Workloads/NonProd` | Dev, staging, QA — mirror prod structure |
| `Sandbox` | Engineer playgrounds, time-limited, budget-capped |
| `Suspended` | Closed-but-retained accounts |

**Splitting axes — pick one primary:**

| Axis | When to use | Trade-off |
|---|---|---|
| By environment (prod/non-prod) | Small org, few apps | Apps share blast radius within an env |
| By team | Org with strong team boundaries, autonomy desired | Cost visibility per app needs tags |
| By application | Strict regulatory or blast-radius isolation per app | Account sprawl, more plumbing |
| By blast-radius (e.g. PCI separate) | Compliance scope reduction | Complex networking and identity |

Most orgs converge on team-or-app primary, environment secondary — one account per (team, environment) pair. Cross-cuts (logging, networking, security tooling) live in dedicated Infrastructure / Security accounts.

**Guardrails via SCP at OU level:**

- Deny root user API actions everywhere except management account break-glass
- Deny disabling CloudTrail, GuardDuty, Config
- Region restrictions — deny all regions except those approved
- Deny IAM user creation in workload accounts (force Identity Center)
- Deny public S3 ACLs at OU level

### 2. Network topology

Three patterns dominate:

| Pattern | Use when | Avoid when |
|---|---|---|
| **Single VPC per account** | Most workloads — even prod | Need multiple isolated tiers in one account |
| **Hub-and-spoke via Transit Gateway** | More than ~3 accounts/VPCs needing connectivity | Tiny footprint with two VPCs (peering is fine) |
| **VPC peering** | Two or three VPCs, low growth, simple routing | More than ~5 VPCs — N² peering becomes unmanageable |

**Transit Gateway is the default at scale.** TGW route tables let you isolate prod from non-prod, isolate sandbox from everything, and route through inspection VPCs. One TGW per region, attachments from each VPC. Spoke VPCs reach the internet via a centralized egress VPC, not their own NAT GWs.

**AWS PrivateLink replaces VPC peering** when one side exposes a service and the other consumes it. PrivateLink is unidirectional, scales to many consumers, and avoids CIDR collisions. Use it for inter-team service exposure within an org and for SaaS consumption.

**VPC sizing.** Allocate a /16 per prod VPC. Resist the urge to be cute with /22 — running out of IPs forces a re-architecture. Plan IP ranges centrally so accounts never collide; this is what enables TGW connectivity.

**Subnet pattern (per AZ):**

- **Public** — ALB, NAT GW, bastion (if used). /24 is plenty.
- **Private (with egress)** — Application compute, ECS tasks, Lambda ENIs. Larger — /20 or bigger.
- **Isolated (no egress)** — RDS, ElastiCache, internal-only resources. /24 to /22.

**NAT Gateway cost trap.** NAT GW charges per hour AND per GB processed. A workload pulling container images, fetching from S3, or hitting DynamoDB through NAT can rack up four-figure monthly bills for what could be free. Mitigations:

- **VPC Gateway Endpoints (free)** for S3 and DynamoDB — always on
- **VPC Interface Endpoints** for SSM, ECR, Secrets Manager, KMS, STS, CloudWatch Logs — costs hourly per endpoint per AZ but eliminates NAT processing for those services
- **Centralized egress VPC** with shared NAT GWs over TGW reduces NAT count from N×3 (per AZ per VPC) to 3 total

**NAT GW per AZ vs centralized egress.** Per-AZ-per-VPC NAT GWs have no SPOF but multiply cost. Centralized egress through one shared VPC is cheaper but introduces a TGW hop and a shared failure domain. Centralized egress wins past ~5 VPCs.

**IPv6.** Dual-stack is increasingly viable and avoids RFC1918 exhaustion. Use it for greenfield. Note that not every AWS service supports IPv6-only.

**Direct Connect vs Site-to-Site VPN.** VPN is faster to set up (hours), runs over public internet, encrypted, ~1.25 Gbps per tunnel. Direct Connect is dedicated fiber, weeks to provision, predictable latency, 1/10/100 Gbps. The pattern: VPN first, replace with Direct Connect if traffic justifies it. Direct Connect + VPN backup is the gold standard for hybrid workloads.

### 3. Identity

**Humans: IAM Identity Center, never IAM users.** Identity Center federates from a corporate IdP (Okta, Entra, Google) or has its own directory. Permission Sets map to roles in member accounts. Engineers get short-lived STS credentials; there are no long-lived access keys to leak.

**Permission Sets — start with these:**

- `AdministratorAccess` — break-glass and Sandbox OU only
- `PowerUserAccess` — most engineers in NonProd
- `ReadOnly` — default for Prod for most engineers
- `Billing` — finance team
- Custom least-privilege sets per service team for prod write access

**Cross-account access for humans** flows through Identity Center, not assume-role chains. Cross-account assume-role is for machines and pipelines.

**Machines: IAM roles, never IAM users.**

| Compute | Identity mechanism |
|---|---|
| EC2 | Instance profile (IAM role attached to instance) |
| Lambda | Execution role |
| ECS task | Task role (and separate execution role for the agent) |
| EKS pod | IRSA (IAM Roles for Service Accounts) — pod-level identity via OIDC |
| GitHub Actions | OIDC federation to an IAM role — no long-lived keys |
| GitLab CI | OIDC federation to an IAM role — same pattern |
| On-prem | IAM Roles Anywhere with a private CA |

The principle: no long-lived credentials anywhere. If the design requires an access key, it is wrong.

**Service control via SCPs (org-level), permission boundaries (account-level), session policies (per-call).** Layered, not redundant — each enforces a different concern.

### 4. Primary compute

There is no single right answer. The decision is driven by request shape, latency tolerance, runtime, team skills, and cost shape.

| Service | Sweet spot | Avoid when |
|---|---|---|
| **Lambda** | Spiky, event-driven, short request, infrequent. Glue, async workers, light APIs. | Sustained high-throughput (cost crosses Fargate around steady ~50% utilization), long jobs, cold-start-sensitive low-latency APIs in Java/.NET, GPU work. |
| **Fargate (ECS or EKS)** | Always-on containerized services, predictable load, team wants containers without nodes. | Sub-100ms scale-up needed, very low cost at very small scale (Lambda cheaper). |
| **ECS on EC2** | Cost-sensitive containerized workloads at steady scale, GPU/specialty instance needs, daemons. | Team lacks capacity-management appetite. |
| **EKS** | Multi-team platform, polyglot workloads, need Kubernetes ecosystem (Helm, operators, CRDs). | Single team, single app — operational overhead not justified. |
| **EC2** | Specialty workloads, legacy lift-and-shift, full OS control, GPU/HPC. | Anything that fits in a container — sunk-cost trap. |
| **App Runner** | Simple HTTP service from a container or repo, no infra appetite. | Need VPC peering complexity, custom networking, or fine-grained scaling. |
| **Batch** | Job-shaped workloads (queue, run, exit), HPC, ML training, scientific compute. | Long-running services. |

**Decision criteria checklist:**

- **Request rate and shape** — spiky vs steady
- **Latency SLO** — cold-start sensitivity
- **Job shape** — request-response, long-running, scheduled, batch
- **Runtime** — Java/.NET cold start poorly on Lambda; Go/Node/Python fine
- **Team familiarity** — Kubernetes operational tax is real
- **Cost shape** — Lambda pay-per-ms vs Fargate pay-per-second-running

A common pattern: Lambda for events and glue, Fargate for HTTP services, Batch for jobs, EKS only when the team is large enough to staff a platform group.

### 5. Primary data store

Match access pattern to data store, not the other way round. The most common architectural mistake is choosing DynamoDB for relational queries or RDS for high-write IoT ingestion.

| Store | Use when | Avoid when |
|---|---|---|
| **RDS (Postgres/MySQL)** | Relational, moderate scale, standard OLTP | Need >64 TB, want Aurora's HA story |
| **Aurora (Postgres/MySQL-compatible)** | Relational, want better availability and read scaling than RDS | Tiny workload — RDS is cheaper |
| **Aurora Serverless v2** | Variable load, dev/test, infrequent prod with burst | Steady high load — provisioned Aurora is cheaper |
| **DynamoDB** | Known access patterns, key-value, document, single-digit ms at any scale | Ad-hoc queries, joins, analytics |
| **DocumentDB** | Existing MongoDB workload, document model | Greenfield — DynamoDB usually wins on AWS |
| **ElastiCache (Redis/Memcached)** | Caching, session store, leaderboards, pub/sub | Primary durable store |
| **OpenSearch** | Full-text search, log analytics, observability data | OLTP — it is not a database |
| **Redshift** | Petabyte-scale OLAP, BI workloads, structured analytics | Operational queries, low concurrency |
| **S3 + Athena (+ Glue)** | Data lake, infrequent ad-hoc analytics, schema-on-read | Sub-second queries |
| **Timestream** | Time-series at scale, IoT telemetry | Ad-hoc analytics across dimensions |
| **Neptune** | Graph queries, relationship-heavy data | Anything tabular — overkill |

**Decision questions:**

- What are the top 3 access patterns and their QPS / latency targets?
- Do queries join across entities? If yes, lean relational.
- Is the access pattern stable or evolving rapidly? DynamoDB punishes evolution; Postgres tolerates it.
- What is the consistency requirement — strong, read-after-write, eventual?
- What is the durability and backup story — PITR, cross-region, retention?
- What does failover look like — and has anyone tested it?

## Networking deep dive

A solution architect must be fluent in VPC mechanics; networking is the layer most often glossed over and most expensive to fix later.

**VPC sizing.** Plan a /16 for any prod VPC. /20 per AZ for the big private subnet, /24 for public and isolated. Document the IP plan centrally so future TGW attachments don't collide.

**Three subnets per AZ:**

- **Public** — only resources that must be internet-reachable: ALB, NAT GW, NLB. No application compute here.
- **Private** — application tier with NAT egress.
- **Isolated** — databases and internal endpoints. No route to NAT or IGW.

**NAT Gateway cost trap (revisited).** NAT GW data processing is ~$0.045/GB. A modest workload pulling 1 TB/month from S3 through NAT pays ~$45/month for free traffic. Always:

- Gateway endpoints for S3 and DynamoDB (free, no data charge)
- Interface endpoints for high-traffic AWS APIs (ECR, CloudWatch Logs, SSM, KMS, STS, Secrets Manager, SQS, SNS)
- Centralized egress past ~5 VPCs

**VPC endpoints — Gateway vs Interface:**

| Type | Services | Cost | Notes |
|---|---|---|---|
| Gateway | S3, DynamoDB | Free | Route table entry; works only same-region |
| Interface | Most other AWS services | ~$7/month per endpoint per AZ + $0.01/GB | ENI in your subnet; security group attached |

Interface endpoints need security group rules — common mistake is not allowing 443 from the workload SG.

**Transit Gateway patterns.**

- One TGW per region, with attachments from each VPC.
- TGW route tables segment traffic. Common segmentation: `prod`, `non-prod`, `shared-services`, `egress`. Spokes attach to one segment route table.
- Inspection VPC pattern: route all east-west or egress traffic through a firewall (AWS Network Firewall, Palo Alto, etc.) before it reaches its destination.
- Cross-region peering on TGW for multi-region setups.

**Direct Connect vs Site-to-Site VPN.** Start with VPN, upgrade to DX when sustained throughput, latency stability, or compliance justifies it. Run DX with VPN backup, not VPN alone, for production hybrid.

## Resilience and HA patterns

**Multi-AZ is the default.** Any prod RDS, ElastiCache, ALB, NAT GW, or compute fleet runs across at least two AZs (three preferred for quorum services). Single-AZ in prod is an accepted risk that needs explicit ADR justification.

**Multi-region is not the default.** It is expensive (data transfer, dual control planes, replication), and most workloads do not need it. Pursue multi-region only when:

- Regulatory requirement for geographic separation
- RTO under one hour with an entire region down
- Latency requirements force the application close to users globally
- Customer contracts mandate it

For most workloads, a strong multi-AZ setup with cross-region backups satisfies the actual requirement.

**DR strategies (in order of cost and capability):**

| Strategy | RTO | RPO | Cost | Mechanism |
|---|---|---|---|---|
| **Backup & Restore** | Hours to days | Hours | Lowest | Restore from backups in DR region |
| **Pilot Light** | Tens of minutes | Minutes | Low | Core services running cold/small; scale up on failover |
| **Warm Standby** | Minutes | Seconds | Medium | Scaled-down full stack running; scale up on failover |
| **Active-Active (Multi-Region)** | Near zero | Near zero | High | Both regions serve traffic; failover is routing |

Pick the strategy that meets the RTO/RPO, not the most ambitious one.

**Cross-region replication mechanisms:**

- **DynamoDB Global Tables** — multi-region active-active, last-writer-wins
- **Aurora Global Database** — fast cross-region read replica, sub-second replication, promotes for failover
- **S3 Cross-Region Replication (CRR)** — async object replication, supports same/cross-account
- **AWS Backup cross-region copies** — for RDS, EBS, EFS, DynamoDB

**Routing failover with Route 53.** Health checks at the endpoint level + failover routing policy + secondary record. Latency-based routing for active-active. Geolocation for regulatory steering.

**Recovery testing.** If failover has never been exercised, it does not work — period. Schedule quarterly game-days that actually fail traffic over. Backups not tested by restore are not backups.

## Security baseline

Non-negotiable controls for any AWS architecture beyond a sandbox:

**Logging and audit:**

- CloudTrail organization trail, all regions, log file validation on, delivered to a dedicated log archive account with bucket-level deny-delete and Object Lock
- Config recorder enabled in every account, every region in use, aggregated to the audit account
- VPC Flow Logs to S3 or CloudWatch Logs (sample rate tuned for cost)

**Threat detection and posture:**

- GuardDuty enabled organization-wide, all regions, with S3, EKS, Malware Protection, RDS, and Lambda data sources as appropriate
- Security Hub enabled with AWS Foundational Security Best Practices and CIS standards, findings aggregated to the audit account
- IAM Access Analyzer enabled per account; review findings as part of architecture reviews
- Inspector for EC2, ECR, and Lambda vulnerability scanning

**Preventive guardrails (SCPs at OU level):**

- Deny root user API actions
- Deny disabling CloudTrail, GuardDuty, Config
- Deny actions in non-approved regions
- Deny creation of IAM users in workload OUs
- Deny public S3 ACLs and BPA disable
- Deny attaching unencrypted EBS volumes

**Encryption:**

- KMS Customer Managed Keys for sensitive data (control over key policy, rotation, access logs)
- Encryption in transit: TLS everywhere, including internal traffic where feasible (service mesh, ALB-to-target)
- Default-encrypted: RDS, EBS, S3 (account-default on)

**Network ingress:**

- No `0.0.0.0/0` ingress on instance security groups. Only ALB, CloudFront, or NLB sit on the edge.
- AWS WAF on every public ALB and CloudFront distribution
- AWS Shield Standard included; Shield Advanced for high-value internet-facing workloads

**Secrets:**

- Secrets Manager for credentials needing rotation; SSM Parameter Store SecureString for static config
- Never bake secrets into AMIs, container images, environment variables in plain text, or repos

## Cost optimization patterns

Cost optimization is structural before it is tactical. The biggest savings come from architectural choices, not from chasing reserved instance coverage percentages.

**Right-sizing.** Compute Optimizer surfaces over-provisioned EC2, EBS, Lambda, and ECS Fargate. Run quarterly. Combine with workload-specific load tests — Compute Optimizer only sees historical utilization.

**Savings Plans vs Reserved Instances.**

| Vehicle | Flexibility | Discount | Best for |
|---|---|---|---|
| **Compute Savings Plans** | EC2, Fargate, Lambda across instance families/regions | Up to ~66% | Most workloads — high flex, broad coverage |
| **EC2 Instance Savings Plans** | One instance family in one region | Up to ~72% | Locked-in steady EC2 fleet |
| **Reserved Instances (RDS, ElastiCache, Redshift, OpenSearch)** | Specific service | Up to ~70% | Steady database workloads |

For most orgs: Compute Savings Plans dominate. Aim for ~70-80% commitment coverage of steady-state usage; leave headroom for spiky/experimental work on on-demand.

**Graviton (ARM).** ~20% cheaper, often better performance per dollar. Native support across RDS, Aurora, ElastiCache, OpenSearch, Lambda, Fargate, EC2. The case for x86-only is now narrow (specific commercial software, certain ML libraries). Default to Graviton for new workloads.

**Spot for fault-tolerant workloads.** Up to 90% discount. Suitable for: Batch, Fargate Spot for stateless services with multiple replicas, EKS with Karpenter mixed pools, CI runners. Not suitable for stateful single-instance workloads.

**S3 storage classes.**

- **Intelligent-Tiering** — default for unknown access patterns; auto-tiers between Frequent, Infrequent, Archive Instant Access. Small monitoring fee per object.
- **Standard-IA / One Zone-IA** — known cold data
- **Glacier Instant Retrieval / Flexible / Deep Archive** — long-term retention; pick by retrieval SLO

Lifecycle policies move objects automatically. For any bucket holding more than ~50 GB of long-tail data, intelligent-tiering or lifecycle pays for itself.

**The NAT Gateway trap (again).** Worth repeating because it routinely costs four figures a month. VPC endpoints first, centralized egress second.

**Tagging strategy.** No tags, no cost visibility, no chargeback. Mandatory tags via SCP — `Environment`, `Owner`, `CostCenter`, `Application`, `DataClassification`. Activate the tags as cost allocation tags. Cost Explorer + AWS Cost and Usage Report (CUR) into Athena for chargeback.

**Non-prod scheduling.** Shut down dev/test environments outside business hours. Instance Scheduler or simple Lambda + EventBridge. ~70% saving on those hours alone.

## Producing an ADR / design doc

Every significant architectural decision is recorded as an ADR. The format is short, opinionated, and dated. The point is to make the decision, the alternatives, and the reasoning legible to whoever inherits the system.

**ADR structure:**

```
# ADR-NNNN: <Short title in present tense>

Date: YYYY-MM-DD
Status: Proposed | Accepted | Superseded by ADR-MMMM
Authors: <names>

## Context
What is the situation? What forces are at play? What are the constraints
(technical, organizational, regulatory, budget)? What is *not* in scope?

## Decision
What was decided. State it plainly, in one or two sentences.

## Considered alternatives
- Alternative A — why rejected
- Alternative B — why rejected
- Alternative C — why rejected (or "deferred")

## Consequences
Positive — what becomes easier or possible
Negative — what becomes harder, what is given up, what is now harder to change
Neutral — facts that follow from the decision

## References
Links to docs, benchmarks, prior ADRs, RFCs.
```

**Example ADR:**

```
# ADR-0042: Use Aurora PostgreSQL Serverless v2 for the Reporting Service

Date: 2026-04-12
Status: Accepted
Authors: Platform team

## Context
The Reporting service is a Postgres-backed read-mostly API that serves
internal dashboards. Traffic is bursty: ~100 QPS during business hours,
near-zero overnight, and spikes to ~2k QPS during quarter-end close (3 days
per quarter). Current state is an over-provisioned RDS db.r6g.2xlarge sized
for the spike, sitting at ~8% CPU 90% of the time. Annual cost ~$18k.

We need a Postgres-compatible store with the same data model, sub-50ms p95
read latency, multi-AZ HA, and meaningful cost reduction.

## Decision
Migrate to Aurora PostgreSQL Serverless v2, ACU range 0.5–16, multi-AZ,
behind RDS Proxy.

## Considered alternatives
- Stay on RDS db.r6g.2xlarge — meets latency, but pays for unused capacity
  ~90% of the time. Rejected on cost.
- Right-size RDS to db.r6g.large with read replicas — cheaper steady-state,
  but quarter-end spikes require manual scaling and risk SLA breach.
  Rejected on operational burden.
- Move to DynamoDB — access patterns include ad-hoc joins for reporting
  queries that are awkward in DynamoDB. Rejected on access-pattern fit.
- Aurora provisioned with auto-scaling read replicas — handles the spike
  but baseline cost is still high. Aurora Serverless v2 dominates on cost
  shape.

## Consequences
Positive
- Estimated annual cost ~$6k, ~67% reduction.
- Auto-scales 0.5–16 ACUs in seconds; quarter-end spike no longer a manual event.
- Same Postgres dialect, no application change beyond connection string.

Negative
- Cold-scale latency: scaling from 0.5 ACU to working size takes seconds;
  first-request latency can briefly exceed 200ms. Mitigated with a minimum
  of 0.5 ACU and RDS Proxy connection pooling.
- Less battle-tested than provisioned Aurora; observed scaling glitches in
  Serverless v1 are largely resolved in v2 but worth monitoring.

Neutral
- Backup, PITR, and snapshot story unchanged from provisioned Aurora.
- Cross-region DR via Aurora Global Database remains available.

## References
- Benchmark notebook: <link>
- Cost model spreadsheet: <link>
- Aurora Serverless v2 docs: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html
- ADR-0011: Reporting service data model
```

ADRs live in the repo (`docs/adr/` per repo convention) under version control. Once Accepted, they are immutable — superseded by a new ADR rather than edited.

## Reference architectures (sketch level)

These are starting points, not blueprints. Each one is a coherent set of decisions for a class of system.

**Public web application.**

- CloudFront in front for TLS termination, caching, and WAF
- ALB in public subnets across 3 AZs
- ECS Fargate services in private subnets — one service per app tier
- Aurora PostgreSQL (multi-AZ) in isolated subnets, accessed via RDS Proxy
- ElastiCache Redis for session store and hot caches
- Cognito User Pool for end-user auth; Identity Center for staff
- Secrets Manager for app credentials, KMS CMKs for at-rest encryption
- CloudWatch Logs + Container Insights; X-Ray for tracing
- Route 53 with health checks, ACM for certificates

**Event-driven backend.**

- API Gateway (HTTP API) in front for ingress, JWT authorizer
- Lambda for synchronous request handling, returns 202 fast
- SQS for durable handoff to async processing
- Lambda worker (or Fargate for sustained work) consuming SQS, with DLQ
- DynamoDB as primary store, on-demand or provisioned with auto-scaling
- EventBridge for fan-out to other consumers and scheduled rules
- S3 for object payloads referenced by events
- CloudWatch alarms on DLQ depth, SQS age, Lambda errors

**Data lake.**

- S3 with bucket-per-zone (raw, curated, consumer) and a strict prefix layout
- Glue Data Catalog as the central metastore
- Glue or EMR for batch ETL; Lambda for small transforms
- Kinesis Data Firehose for streaming ingestion to S3 with Parquet conversion
- Athena for ad-hoc SQL; Redshift Serverless for heavier BI workloads
- Lake Formation for fine-grained access control
- QuickSight or third-party BI consuming Athena/Redshift

**Multi-account landing zone.**

- Control Tower-managed Organization with management, log-archive, audit accounts
- IAM Identity Center federated to corporate IdP
- OUs: Security, Infrastructure, Workloads/Prod, Workloads/NonProd, Sandbox, Suspended
- Networking account hosts the central Transit Gateway; spoke accounts attach VPCs
- Centralized egress VPC with NAT GWs and a Network Firewall
- Central CI/CD account with cross-account deploy roles into workload accounts
- Tagging policy enforced by SCP; Cost and Usage Report into the audit account

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

**Compute selection at a glance:**

| Need | Service |
|---|---|
| Spiky events, glue, short jobs | Lambda |
| Containerized HTTP service, predictable load | Fargate |
| Containerized service, cost-sensitive at scale | ECS on EC2 |
| Multi-team Kubernetes platform | EKS |
| Simple HTTP service from a repo or container | App Runner |
| Job-shaped batch / HPC | Batch |
| Specialty / legacy / GPU-heavy | EC2 |

**Data store selection at a glance:**

| Need | Service |
|---|---|
| Relational, moderate scale | RDS Postgres/MySQL |
| Relational, high availability and read scale | Aurora |
| Relational, variable load | Aurora Serverless v2 |
| Key-value, document, predictable access pattern | DynamoDB |
| Cache, session store | ElastiCache Redis |
| Full-text search, log analytics | OpenSearch |
| Petabyte OLAP, BI | Redshift |
| Schema-on-read data lake | S3 + Glue + Athena |
| Time-series at scale | Timestream |
| Graph | Neptune |

**Networking selection at a glance:**

| Need | Service |
|---|---|
| Single-VPC connectivity | Stay simple |
| 2-3 VPCs cross-account | VPC peering |
| Many VPCs, scaling | Transit Gateway |
| Expose a service unidirectionally | PrivateLink |
| Hybrid, latency-stable | Direct Connect (with VPN backup) |
| Hybrid, fast to set up | Site-to-Site VPN |
| Free egress to AWS services | VPC endpoints (Gateway for S3/DDB, Interface otherwise) |

**Identity selection at a glance:**

| Principal | Mechanism |
|---|---|
| Human, internal | IAM Identity Center federated to IdP |
| EC2 | Instance profile |
| Lambda | Execution role |
| ECS task | Task role |
| EKS pod | IRSA |
| GitHub/GitLab CI | OIDC federation to IAM role |
| On-prem workload | IAM Roles Anywhere |

**Cross-references.** For implementation, see the `terraform-aws` skill (module patterns, provider config, state) and `terragrunt-multi-account` skill (DRY config across accounts and regions, account vending, remote state per account). This skill produces the design inputs; those skills turn them into running infrastructure.
