# Account Topology

Default to multi-account from day one. A single account is acceptable only for individual side projects and disposable demos. Multi-account is non-negotiable for anything with production data, multiple environments, or more than one team.

## Why multi-account

Account is the strongest blast-radius boundary AWS offers — stronger than VPC, IAM policy, or SCP. It contains IAM, quotas, billing, and most service limits. Splitting by account makes "compromise in dev cannot reach prod" structural, not policy-based.

## Foundation: AWS Organizations + Control Tower + IAM Identity Center

Control Tower provides a managed landing zone — an Organization, mandatory accounts (management, log archive, audit), guardrails (SCPs and Config rules), and Account Factory for vending. IAM Identity Center (formerly AWS SSO) is the single identity plane for humans across all accounts.

## OU design — start here

| OU | Purpose |
|---|---|
| `Security` | Log archive account, audit/security tooling account |
| `Infrastructure` | Shared services — networking hub, central CI/CD, shared DNS |
| `Workloads/Prod` | Production workload accounts, one per app or per team |
| `Workloads/NonProd` | Dev, staging, QA — mirror prod structure |
| `Sandbox` | Engineer playgrounds, time-limited, budget-capped |
| `Suspended` | Closed-but-retained accounts |

## Splitting axes — pick one primary

| Axis | When to use | Trade-off |
|---|---|---|
| By environment (prod/non-prod) | Small org, few apps | Apps share blast radius within an env |
| By team | Org with strong team boundaries, autonomy desired | Cost visibility per app needs tags |
| By application | Strict regulatory or blast-radius isolation per app | Account sprawl, more plumbing |
| By blast-radius (e.g. PCI separate) | Compliance scope reduction | Complex networking and identity |

Most organizations converge on team-or-app primary, environment secondary — one account per (team, environment) pair. Cross-cuts (logging, networking, security tooling) live in dedicated Infrastructure / Security accounts.

## Guardrails via SCP at OU level

- Deny root user API actions everywhere except management account break-glass
- Deny disabling CloudTrail, GuardDuty, Config
- Region restrictions — deny all regions except those approved
- Deny IAM user creation in workload accounts (force Identity Center)
- Deny public S3 ACLs at OU level
- Deny attaching unencrypted EBS volumes
- Deny actions in non-approved regions

## Implementation

For day-2 operations and IaC patterns to vend and manage these accounts, see the `terragrunt-multi-account` skill (DRY config across accounts and regions, account vending, remote state per account).
