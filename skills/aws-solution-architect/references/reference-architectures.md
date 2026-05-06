# Reference Architectures (Sketch Level)

These are starting points, not blueprints. Each one is a coherent set of decisions for a class of system. Implementation lives in the `terraform-aws` and `terragrunt-multi-account` skills.

## Public web application

- CloudFront in front for TLS termination, caching, and WAF
- ALB in public subnets across 3 AZs
- ECS Fargate services in private subnets — one service per app tier
- Aurora PostgreSQL (multi-AZ) in isolated subnets, accessed via RDS Proxy
- ElastiCache Redis for session store and hot caches
- Cognito User Pool for end-user auth; Identity Center for staff
- Secrets Manager for app credentials, KMS CMKs for at-rest encryption
- CloudWatch Logs + Container Insights; X-Ray for tracing
- Route 53 with health checks, ACM for certificates

## Event-driven backend

- API Gateway (HTTP API) in front for ingress, JWT authorizer
- Lambda for synchronous request handling, returns 202 fast
- SQS for durable handoff to async processing
- Lambda worker (or Fargate for sustained work) consuming SQS, with DLQ
- DynamoDB as primary store, on-demand or provisioned with auto-scaling
- EventBridge for fan-out to other consumers and scheduled rules
- S3 for object payloads referenced by events
- CloudWatch alarms on DLQ depth, SQS age, Lambda errors

## Data lake

- S3 with bucket-per-zone (raw, curated, consumer) and a strict prefix layout
- Glue Data Catalog as the central metastore
- Glue or EMR for batch ETL; Lambda for small transforms
- Kinesis Data Firehose for streaming ingestion to S3 with Parquet conversion
- Athena for ad-hoc SQL; Redshift Serverless for heavier BI workloads
- Lake Formation for fine-grained access control
- QuickSight or third-party BI consuming Athena/Redshift

## Multi-account landing zone

- Control Tower-managed Organization with management, log-archive, audit accounts
- IAM Identity Center federated to corporate IdP
- OUs: Security, Infrastructure, Workloads/Prod, Workloads/NonProd, Sandbox, Suspended
- Networking account hosts the central Transit Gateway; spoke accounts attach VPCs
- Centralized egress VPC with NAT GWs and a Network Firewall
- Central CI/CD account with cross-account deploy roles into workload accounts
- Tagging policy enforced by SCP; Cost and Usage Report into the audit account
