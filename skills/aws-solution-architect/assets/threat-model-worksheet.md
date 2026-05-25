# Threat Model Worksheet (STRIDE-lite)

System: ____________________
Author: ____________________
Date: YYYY-MM-DD

## Scope

One paragraph. What is in scope (components, data flows, trust boundaries) and what is not.

## Components

List the components and their trust boundary. A trust boundary is where data crosses from one principal to another (e.g., internet → ALB, app → DB, account A → account B).

| # | Component | AWS service | Trust boundary crossed |
|---|---|---|---|
| 1 | <e.g. Public ALB> | ALB | Internet → public subnet |
| 2 | <e.g. App service> | Fargate | Public → private subnet |
| 3 | <e.g. Primary DB> | Aurora | Private → isolated subnet |
| 4 | <e.g. Object store> | S3 | App → S3 (cross-AZ) |

## STRIDE per component

For each component, list at least one risk per STRIDE category and the mitigation. "N/A" is acceptable but must be justified.

### Component 1: <name>

| Threat | Risk | Mitigation |
|---|---|---|
| **S**poofing — impersonating a principal | <e.g. attacker impersonates a service caller> | <e.g. mTLS via service mesh; SigV4; Cognito JWT> |
| **T**ampering — modifying data or code in flight or at rest | | |
| **R**epudiation — denying an action without trace | | |
| **I**nformation disclosure — exposing data to the wrong principal | | |
| **D**enial of service — exhausting resources | | |
| **E**levation of privilege — gaining capabilities not granted | | |

### Component 2: <name>

| Threat | Risk | Mitigation |
|---|---|---|
| **S**poofing | | |
| **T**ampering | | |
| **R**epudiation | | |
| **I**nformation disclosure | | |
| **D**enial of service | | |
| **E**levation of privilege | | |

### Component 3: <name>

| Threat | Risk | Mitigation |
|---|---|---|
| **S**poofing | | |
| **T**ampering | | |
| **R**epudiation | | |
| **I**nformation disclosure | | |
| **D**enial of service | | |
| **E**levation of privilege | | |

## Cross-cutting concerns

- **Secrets handling** — where are credentials stored, rotated, and audited?
- **Logging and audit** — does CloudTrail / app log capture every privileged action with attribution?
- **Blast radius** — if a single component's identity is compromised, what is reachable?
- **Supply chain** — base images, dependencies, IaC modules — what is the provenance?

## Open issues

- <Issue 1 — owner, decision needed by date>
- <Issue 2 — owner, decision needed by date>

## References

- ADRs for the decisions that shape the threat surface
- Architecture review checklist results
- Related security incidents or near-misses
