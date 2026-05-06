# Identity

The principle: no long-lived credentials anywhere. If the design requires an access key, it is wrong.

## Humans: IAM Identity Center, never IAM users

Identity Center federates from a corporate IdP (Okta, Entra, Google) or has its own directory. Permission Sets map to roles in member accounts. Engineers get short-lived STS credentials; there are no long-lived access keys to leak.

### Permission Sets — start with these

- `AdministratorAccess` — break-glass and Sandbox OU only
- `PowerUserAccess` — most engineers in NonProd
- `ReadOnly` — default for Prod for most engineers
- `Billing` — finance team
- Custom least-privilege sets per service team for prod write access

Cross-account access for humans flows through Identity Center, not assume-role chains. Cross-account assume-role is for machines and pipelines.

## Machines: IAM roles, never IAM users

| Compute | Identity mechanism |
|---|---|
| EC2 | Instance profile (IAM role attached to instance) |
| Lambda | Execution role |
| ECS task | Task role (and separate execution role for the agent) |
| EKS pod | IRSA (IAM Roles for Service Accounts) — pod-level identity via OIDC |
| GitHub Actions | OIDC federation to an IAM role — no long-lived keys |
| GitLab CI | OIDC federation to an IAM role — same pattern |
| On-prem | IAM Roles Anywhere with a private CA |

## Layered authorization

Service control policies (SCPs) at the OU level set the outer boundary of what is permissible. Permission boundaries scope what an IAM role inside an account can grant. Session policies narrow per-call. The three are layered, not redundant — each enforces a different concern.

| Layer | Scope | Who controls |
|---|---|---|
| SCP | OU / org | Security / cloud platform team |
| Permission boundary | Account / role | Account admin |
| Identity policy | Role / user | Workload team |
| Session policy | Per assumed-role session | Caller |

## Identity selection at a glance

| Principal | Mechanism |
|---|---|
| Human, internal | IAM Identity Center federated to IdP |
| EC2 | Instance profile |
| Lambda | Execution role |
| ECS task | Task role |
| EKS pod | IRSA |
| GitHub/GitLab CI | OIDC federation to IAM role |
| On-prem workload | IAM Roles Anywhere |
