# Well-Architected Framework — Question Sets

The Well-Architected Framework (WAF) has six pillars. Most teams treat it as a checkbox audit; an architect treats it as a question set used during design. For each pillar, the questions below are asked before the design is frozen. The output of a WAF review is a list of accepted risks plus a backlog of remediations, not a passing grade.

## Operational Excellence

- How do operators discover that something is broken — alerts, dashboards, customer reports? What is the mean time to detection target?
- How is configuration managed — IaC end-to-end, or are there click-ops corners? Where are the gaps?
- How are runbooks kept current? Who runs game-days?
- What is the deploy cadence and rollback time? Can the team deploy on a Friday afternoon?
- Are post-incident reviews blameless and do they produce concrete action items?

## Security

- What is the blast radius of a compromised IAM principal in the worst-case account?
- Is data encrypted in transit and at rest by default? Where is it not, and why?
- How would a privileged credential leak be detected and rotated within an hour?
- Are there `0.0.0.0/0` ingress rules? On what, and is there a WAF in front?
- Is CloudTrail organization-wide, immutable, and centralized? Is GuardDuty on in every account and region in use?

## Reliability

- What is the RTO and RPO for each tier of service, and is the architecture actually capable of meeting them?
- What happens when a single AZ fails? A region? A dependency?
- Are failures tested — chaos days, fail-over rehearsals — or only theoretical?
- Are there hard quotas (Lambda concurrency, RDS connections, ENI limits) that throttle the system before infrastructure does?
- Is there backpressure on every queue and async boundary?

## Performance Efficiency

- Has the access pattern been characterized before the data store was chosen, or was it the other way round?
- Where are the latency SLOs and how are they measured (p50, p95, p99)?
- Is compute right-sized? Is Graviton (ARM) on the table?
- Is caching present where it would actually help (CloudFront, ElastiCache, DAX), or is it cargo-culted?
- Are there hot keys, hot partitions, or hot shards lurking?

## Cost Optimization

- Is there a tagging strategy enforced via SCP and used by Cost Explorer?
- Are Compute Savings Plans applied where utilization is steady?
- Where is NAT Gateway processing data that should be going through a VPC endpoint?
- Are non-prod environments shutting down outside business hours?
- Is S3 Intelligent-Tiering on by default for unknown access patterns?

## Sustainability

- Is the workload region chosen with carbon intensity in mind where it does not violate latency or compliance?
- Are idle resources hunted regularly (orphaned EBS, unused EIPs, dev environments left on)?
- Is right-sizing continuous, or a one-time exercise?
- Are managed services preferred over self-managed where they shift utilization to AWS's shared fleet?
