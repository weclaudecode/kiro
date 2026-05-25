# Architecture Review Checklist

WAF-driven review. The reviewer ticks each item, marks N/A with reason, or files a remediation. The output is a list of accepted risks plus a remediation backlog — not a passing grade.

System: ____________________
Reviewer: ____________________
Date: YYYY-MM-DD

## Operational Excellence

- [ ] Infrastructure is fully defined as code (Terraform/Terragrunt/CloudFormation/CDK)
- [ ] No click-ops drift — IaC is the source of truth, drift detection in place
- [ ] CI/CD pipeline deploys all environments; manual prod deploy is a break-glass path only
- [ ] Rollback is documented and tested; rollback time meets target
- [ ] Runbooks exist for the top 5 failure modes and are dated within last 6 months
- [ ] Game-day or chaos exercises are scheduled at least quarterly
- [ ] Post-incident review process is blameless and produces tracked action items
- [ ] Dashboards and alerts exist for the SLIs that matter; alerts route to the on-call
- [ ] MTTD and MTTR targets are set per service tier

## Security

- [ ] CloudTrail organization trail enabled, all regions, log-file validation on
- [ ] CloudTrail logs delivered to a dedicated log archive account with Object Lock + deny-delete
- [ ] AWS Config recorder enabled in every account/region, aggregated to audit account
- [ ] GuardDuty enabled organization-wide, all regions, with relevant data sources
- [ ] Security Hub enabled with AWS FSBP + CIS standards
- [ ] IAM Access Analyzer enabled, findings reviewed
- [ ] No IAM users in workload accounts (Identity Center for humans, roles for machines)
- [ ] No long-lived access keys for CI — OIDC federation in use
- [ ] SCPs in place: deny-root, deny-disable-{CloudTrail,GuardDuty,Config}, region restriction, deny-public-S3
- [ ] All data encrypted at rest (KMS CMK for sensitive data)
- [ ] All data in transit uses TLS; internal traffic encrypted where feasible
- [ ] Secrets are in Secrets Manager / SSM SecureString — never in env vars in plain text or repos
- [ ] No `0.0.0.0/0` ingress on instance security groups — edge through ALB/CloudFront/NLB only
- [ ] AWS WAF on every public ALB and CloudFront distribution
- [ ] Threat model exists for the system (STRIDE-lite or equivalent)

## Reliability

- [ ] Multi-AZ for every prod stateful service (RDS, ElastiCache, NAT GW, ALB, compute fleet)
- [ ] RTO and RPO are documented per tier and the design demonstrably meets them
- [ ] Failover has been tested — not just theoretically possible
- [ ] Backups exist and have been restored within the last quarter
- [ ] Cross-region backup copies for critical data
- [ ] Service quotas reviewed against peak load (Lambda concurrency, RDS connections, ENI limits)
- [ ] Backpressure on every queue and async boundary; DLQs configured
- [ ] Health checks and dependency timeouts are set; cascading-failure scenarios considered
- [ ] Multi-region strategy documented — even if the answer is "not pursued"

## Performance Efficiency

- [ ] Top-3 access patterns documented before the data store was chosen
- [ ] Latency SLOs (p50/p95/p99) defined and measured
- [ ] Compute right-sized; Compute Optimizer findings reviewed
- [ ] Graviton (ARM) considered and adopted where supported
- [ ] Caching layer in place where it materially helps (CloudFront, ElastiCache, DAX)
- [ ] Hot keys / hot partitions / hot shards analyzed and mitigated
- [ ] Load test exists at expected peak + 50%

## Cost Optimization

- [ ] Tagging strategy defined and enforced via SCP (Environment, Owner, CostCenter, Application, DataClassification)
- [ ] Cost allocation tags activated; Cost Explorer and CUR (into Athena) used
- [ ] Compute Savings Plans coverage at ~70-80% of steady-state
- [ ] VPC Gateway Endpoints for S3 and DynamoDB enabled
- [ ] VPC Interface Endpoints for noisy AWS APIs (ECR, CloudWatch Logs, SSM, KMS, STS, Secrets Manager)
- [ ] Centralized egress VPC if more than ~5 VPCs
- [ ] S3 Intelligent-Tiering or lifecycle policies on long-tail data
- [ ] Non-prod environments shut down outside business hours
- [ ] Idle resources hunted (orphaned EBS, unused EIPs, stale snapshots)

## Sustainability

- [ ] Region choice considers carbon intensity where it does not violate latency or compliance
- [ ] Right-sizing is continuous, not a one-time exercise
- [ ] Managed services preferred over self-managed where appropriate
- [ ] Idle resources reviewed quarterly

---

## Findings summary

| Area | Status | Notes |
|---|---|---|
| Operational Excellence | Pass / Pass with risks / Fail | |
| Security | | |
| Reliability | | |
| Performance | | |
| Cost | | |
| Sustainability | | |

## Accepted risks

- <Risk 1 — owner, review-by date>
- <Risk 2 — owner, review-by date>

## Remediation backlog

- <Item 1 — priority, owner, target date>
- <Item 2 — priority, owner, target date>
