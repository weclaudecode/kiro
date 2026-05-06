# Cost Optimization

Cost optimization is structural before it is tactical. The biggest savings come from architectural choices, not from chasing reserved instance coverage percentages.

## Right-sizing

Compute Optimizer surfaces over-provisioned EC2, EBS, Lambda, and ECS Fargate. It is run quarterly. Combine with workload-specific load tests — Compute Optimizer only sees historical utilization.

## Savings Plans vs Reserved Instances

| Vehicle | Flexibility | Discount | Best for |
|---|---|---|---|
| **Compute Savings Plans** | EC2, Fargate, Lambda across instance families/regions | Up to ~66% | Most workloads — high flex, broad coverage |
| **EC2 Instance Savings Plans** | One instance family in one region | Up to ~72% | Locked-in steady EC2 fleet |
| **Reserved Instances (RDS, ElastiCache, Redshift, OpenSearch)** | Specific service | Up to ~70% | Steady database workloads |

For most orgs: Compute Savings Plans dominate. Aim for ~70-80% commitment coverage of steady-state usage; leave headroom for spiky/experimental work on on-demand.

## Graviton (ARM)

~20% cheaper, often better performance per dollar. Native support across RDS, Aurora, ElastiCache, OpenSearch, Lambda, Fargate, EC2. The case for x86-only is now narrow (specific commercial software, certain ML libraries). Default to Graviton for new workloads.

## Spot for fault-tolerant workloads

Up to 90% discount. Suitable for: Batch, Fargate Spot for stateless services with multiple replicas, EKS with Karpenter mixed pools, CI runners. Not suitable for stateful single-instance workloads.

## S3 storage classes

- **Intelligent-Tiering** — default for unknown access patterns; auto-tiers between Frequent, Infrequent, Archive Instant Access. Small monitoring fee per object.
- **Standard-IA / One Zone-IA** — known cold data
- **Glacier Instant Retrieval / Flexible / Deep Archive** — long-term retention; pick by retrieval SLO

Lifecycle policies move objects automatically. For any bucket holding more than ~50 GB of long-tail data, intelligent-tiering or lifecycle pays for itself.

## The NAT Gateway trap

Worth repeating because it routinely costs four figures a month. VPC endpoints first, centralized egress second. See `networking.md` for the full mitigation pattern.

## Tagging strategy

No tags, no cost visibility, no chargeback. Mandatory tags via SCP — `Environment`, `Owner`, `CostCenter`, `Application`, `DataClassification`. Activate the tags as cost allocation tags. Cost Explorer + AWS Cost and Usage Report (CUR) into Athena for chargeback.

## Non-prod scheduling

Shut down dev/test environments outside business hours. Instance Scheduler or simple Lambda + EventBridge. ~70% saving on those hours alone.
