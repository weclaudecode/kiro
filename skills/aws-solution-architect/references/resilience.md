# Resilience and HA Patterns

## Multi-AZ is the default

Any prod RDS, ElastiCache, ALB, NAT GW, or compute fleet runs across at least two AZs (three preferred for quorum services). Single-AZ in prod is an accepted risk that needs explicit ADR justification.

## Multi-region is not the default

It is expensive (data transfer, dual control planes, replication), and most workloads do not need it. Pursue multi-region only when:

- Regulatory requirement for geographic separation
- RTO under one hour with an entire region down
- Latency requirements force the application close to users globally
- Customer contracts mandate it

For most workloads, a strong multi-AZ setup with cross-region backups satisfies the actual requirement.

## DR strategies (in order of cost and capability)

| Strategy | RTO | RPO | Cost | Mechanism |
|---|---|---|---|---|
| **Backup & Restore** | Hours to days | Hours | Lowest | Restore from backups in DR region |
| **Pilot Light** | Tens of minutes | Minutes | Low | Core services running cold/small; scale up on failover |
| **Warm Standby** | Minutes | Seconds | Medium | Scaled-down full stack running; scale up on failover |
| **Active-Active (Multi-Region)** | Near zero | Near zero | High | Both regions serve traffic; failover is routing |

Pick the strategy that meets the RTO/RPO, not the most ambitious one.

## Cross-region replication mechanisms

- **DynamoDB Global Tables** — multi-region active-active, last-writer-wins
- **Aurora Global Database** — fast cross-region read replica, sub-second replication, promotes for failover
- **S3 Cross-Region Replication (CRR)** — async object replication, supports same/cross-account
- **AWS Backup cross-region copies** — for RDS, EBS, EFS, DynamoDB

## Routing failover with Route 53

Health checks at the endpoint level + failover routing policy + secondary record. Latency-based routing for active-active. Geolocation for regulatory steering.

## Recovery testing

If failover has never been exercised, it does not work — period. Quarterly game-days that actually fail traffic over are scheduled. Backups not tested by restore are not backups.

## Reliability questions to answer

- What is the RTO and RPO per tier?
- What happens when a single AZ fails? A region? A dependency?
- Are quotas (Lambda concurrency, RDS connections, ENI limits) sized above peak?
- Is there backpressure on every queue and async boundary?
