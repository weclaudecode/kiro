# ADR-NNNN: <Short title in present tense>

Date: YYYY-MM-DD
Status: Proposed | Accepted | Superseded by ADR-MMMM
Authors: <names>

## Context

What is the situation? What forces are at play? What are the constraints
(technical, organizational, regulatory, budget)? What is *not* in scope?

State the problem in plain language. Quantify where possible: traffic
shape, latency targets, current cost, team size, deadline. Link to the
design doc, prior ADRs, or RFCs that frame this decision.

## Decision

What was decided. State it plainly, in one or two sentences.

## Considered alternatives

- **Alternative A** — short description, why rejected (or "deferred")
- **Alternative B** — short description, why rejected
- **Alternative C** — short description, why rejected

Each alternative names what was looked at and the specific reason it lost.
"Not chosen" is not enough — record the trade-off.

## Consequences

**Positive**

- What becomes easier or possible
- Quantified wins (cost, latency, ops burden) where known

**Negative**

- What becomes harder, what is given up
- What is now harder to change later
- Mitigations for the worst negatives

**Neutral**

- Facts that follow from the decision and are worth recording

## References

- Links to docs, benchmarks, prior ADRs, RFCs
- Cost models, load test results, vendor docs

---

ADRs live in the repo (`docs/adr/` per repo convention) under version
control. Once **Accepted**, they are immutable — superseded by a new ADR
rather than edited.

---

## Worked example

The example below illustrates how a complete ADR reads. It is not a
template field — it is the finished form.

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

The team needs a Postgres-compatible store with the same data model,
sub-50ms p95 read latency, multi-AZ HA, and meaningful cost reduction.

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
- Auto-scales 0.5–16 ACUs in seconds; quarter-end spike no longer a manual
  event.
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
