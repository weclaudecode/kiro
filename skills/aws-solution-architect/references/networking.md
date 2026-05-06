# Networking

A solution architect must be fluent in VPC mechanics; networking is the layer most often glossed over and most expensive to fix later.

## Three patterns dominate

| Pattern | Use when | Avoid when |
|---|---|---|
| **Single VPC per account** | Most workloads — even prod | Need multiple isolated tiers in one account |
| **Hub-and-spoke via Transit Gateway** | More than ~3 accounts/VPCs needing connectivity | Tiny footprint with two VPCs (peering is fine) |
| **VPC peering** | Two or three VPCs, low growth, simple routing | More than ~5 VPCs — N² peering becomes unmanageable |

**Transit Gateway is the default at scale.** TGW route tables let an architect isolate prod from non-prod, isolate sandbox from everything, and route through inspection VPCs. One TGW per region, attachments from each VPC. Spoke VPCs reach the internet via a centralized egress VPC, not their own NAT GWs.

**AWS PrivateLink replaces VPC peering** when one side exposes a service and the other consumes it. PrivateLink is unidirectional, scales to many consumers, and avoids CIDR collisions. It is the right tool for inter-team service exposure within an org and for SaaS consumption.

## VPC sizing

Allocate a /16 per prod VPC. Resist the urge to be cute with /22 — running out of IPs forces a re-architecture. IP ranges are planned centrally so accounts never collide; this is what enables TGW connectivity.

## Subnet pattern (per AZ)

- **Public** — only resources that must be internet-reachable: ALB, NAT GW, NLB. No application compute here. /24 is plenty.
- **Private (with egress)** — application tier with NAT egress. Application compute, ECS tasks, Lambda ENIs. Larger — /20 or bigger.
- **Isolated (no egress)** — RDS, ElastiCache, internal-only resources. No route to NAT or IGW. /24 to /22.

## NAT Gateway cost trap

NAT GW charges per hour AND per GB processed (~$0.045/GB). A workload pulling container images, fetching from S3, or hitting DynamoDB through NAT can rack up four-figure monthly bills for what could be free traffic. Mitigations:

- **VPC Gateway Endpoints (free)** for S3 and DynamoDB — always on
- **VPC Interface Endpoints** for SSM, ECR, Secrets Manager, KMS, STS, CloudWatch Logs, SQS, SNS — costs hourly per endpoint per AZ but eliminates NAT processing for those services
- **Centralized egress VPC** with shared NAT GWs over TGW reduces NAT count from N×3 (per AZ per VPC) to 3 total

**NAT GW per AZ vs centralized egress.** Per-AZ-per-VPC NAT GWs have no SPOF but multiply cost. Centralized egress through one shared VPC is cheaper but introduces a TGW hop and a shared failure domain. Centralized egress wins past ~5 VPCs.

## VPC endpoints — Gateway vs Interface

| Type | Services | Cost | Notes |
|---|---|---|---|
| Gateway | S3, DynamoDB | Free | Route table entry; works only same-region |
| Interface | Most other AWS services | ~$7/month per endpoint per AZ + $0.01/GB | ENI in your subnet; security group attached |

Interface endpoints need security group rules — a common mistake is not allowing 443 from the workload SG.

## Transit Gateway patterns

- One TGW per region, with attachments from each VPC.
- TGW route tables segment traffic. Common segmentation: `prod`, `non-prod`, `shared-services`, `egress`. Spokes attach to one segment route table.
- **Inspection VPC pattern**: route all east-west or egress traffic through a firewall (AWS Network Firewall, Palo Alto, etc.) before it reaches its destination.
- Cross-region peering on TGW for multi-region setups.

## IPv6

Dual-stack is increasingly viable and avoids RFC1918 exhaustion. Use it for greenfield. Note that not every AWS service supports IPv6-only.

## Hybrid: Direct Connect vs Site-to-Site VPN

VPN is faster to set up (hours), runs over public internet, encrypted, ~1.25 Gbps per tunnel. Direct Connect is dedicated fiber, weeks to provision, predictable latency, 1/10/100 Gbps. The pattern: VPN first, replace with Direct Connect when sustained throughput, latency stability, or compliance justifies it. Direct Connect + VPN backup is the gold standard for hybrid workloads in production.

## Networking selection at a glance

| Need | Service |
|---|---|
| Single-VPC connectivity | Stay simple |
| 2-3 VPCs cross-account | VPC peering |
| Many VPCs, scaling | Transit Gateway |
| Expose a service unidirectionally | PrivateLink |
| Hybrid, latency-stable | Direct Connect (with VPN backup) |
| Hybrid, fast to set up | Site-to-Site VPN |
| Free egress to AWS services | VPC endpoints (Gateway for S3/DDB, Interface otherwise) |
