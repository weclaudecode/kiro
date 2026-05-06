# Compute Selection

There is no single right answer. The decision is driven by request shape, latency tolerance, runtime, team skills, and cost shape.

## Decision matrix

| Service | Sweet spot | Avoid when |
|---|---|---|
| **Lambda** | Spiky, event-driven, short request, infrequent. Glue, async workers, light APIs. | Sustained high-throughput (cost crosses Fargate around steady ~50% utilization), long jobs, cold-start-sensitive low-latency APIs in Java/.NET, GPU work. |
| **Fargate (ECS or EKS)** | Always-on containerized services, predictable load, team wants containers without nodes. | Sub-100ms scale-up needed, very low cost at very small scale (Lambda cheaper). |
| **ECS on EC2** | Cost-sensitive containerized workloads at steady scale, GPU/specialty instance needs, daemons. | Team lacks capacity-management appetite. |
| **EKS** | Multi-team platform, polyglot workloads, need Kubernetes ecosystem (Helm, operators, CRDs). | Single team, single app — operational overhead not justified. |
| **EC2** | Specialty workloads, legacy lift-and-shift, full OS control, GPU/HPC. | Anything that fits in a container — sunk-cost trap. |
| **App Runner** | Simple HTTP service from a container or repo, no infra appetite. | Need VPC peering complexity, custom networking, or fine-grained scaling. |
| **Batch** | Job-shaped workloads (queue, run, exit), HPC, ML training, scientific compute. | Long-running services. |

## Decision criteria checklist

- **Request rate and shape** — spiky vs steady
- **Latency SLO** — cold-start sensitivity
- **Job shape** — request-response, long-running, scheduled, batch
- **Runtime** — Java/.NET cold start poorly on Lambda; Go/Node/Python fine
- **Team familiarity** — Kubernetes operational tax is real
- **Cost shape** — Lambda pay-per-ms vs Fargate pay-per-second-running

## Common pattern

A common pattern in mature organizations: Lambda for events and glue, Fargate for HTTP services, Batch for jobs, EKS only when the team is large enough to staff a platform group.

## Compute selection at a glance

| Need | Service |
|---|---|
| Spiky events, glue, short jobs | Lambda |
| Containerized HTTP service, predictable load | Fargate |
| Containerized service, cost-sensitive at scale | ECS on EC2 |
| Multi-team Kubernetes platform | EKS |
| Simple HTTP service from a repo or container | App Runner |
| Job-shaped batch / HPC | Batch |
| Specialty / legacy / GPU-heavy | EC2 |
