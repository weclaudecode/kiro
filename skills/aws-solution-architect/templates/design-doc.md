# Design Doc: <System or feature name>

Author: <name>
Date: YYYY-MM-DD
Status: Draft | In review | Approved
Reviewers: <names>

## Problem statement

One paragraph. What problem is being solved, for whom, and why now? What
happens if nothing is done?

## Constraints

Bullet the hard constraints that bound the design space.

- **Functional** — must-have capabilities
- **Performance** — latency SLO, throughput target, scale ceiling
- **Availability** — RTO/RPO, multi-AZ, multi-region
- **Security/compliance** — data classification, regulatory scope (PCI, HIPAA, SOC 2)
- **Budget** — annual cost ceiling, FinOps targets
- **Timeline** — go-live date, dependencies
- **Team/org** — skills available, on-call capacity, existing tooling

## Proposed architecture

Text-form sketch of the architecture. List the components, their AWS
service, and the data/control flow between them. Reference the relevant
high-leverage decisions (account topology, network, identity, compute,
data) explicitly.

```
[Client] → CloudFront → ALB → Fargate (service-a) → Aurora (writer)
                              ↓
                              SQS → Lambda worker → DynamoDB
```

For each major component, state:

- **What** — service and tier
- **Why** — what alternative was rejected and why (link the ADR)
- **Cost shape** — pay-per-use, reserved, savings-plan candidate

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| <risk 1> | Low/Med/High | Low/Med/High | <how it is mitigated or accepted> |
| <risk 2> | | | |

## Open questions

- <Question 1 — owner, decision needed by date>
- <Question 2 — owner, decision needed by date>

## Cost estimate

Order-of-magnitude monthly cost at expected steady-state. List the top
~5 cost drivers and an annual total.

| Component | Driver | $/month |
|---|---|---|
| Compute | <e.g. 4× Fargate tasks 24/7> | $X |
| Data | <e.g. Aurora db.r6g.large multi-AZ> | $X |
| Network | <e.g. NAT GW + endpoints + egress> | $X |
| Storage | <e.g. S3 1 TB intelligent-tiering> | $X |
| Other | <observability, KMS, secrets, etc.> | $X |
| **Total** | | **$X** |

Annual: $X. Notes on assumptions (utilization, growth, savings plan
coverage).

## References

- Related ADRs
- Prior design docs
- Benchmarks, vendor docs
