# Security Baseline

Non-negotiable controls for any AWS architecture beyond a sandbox. For deeper code-level audit and vulnerability review, see the `security-code-reviewer` skill — this baseline covers the architectural floor.

## Logging and audit

- CloudTrail organization trail, all regions, log file validation on, delivered to a dedicated log archive account with bucket-level deny-delete and Object Lock
- Config recorder enabled in every account, every region in use, aggregated to the audit account
- VPC Flow Logs to S3 or CloudWatch Logs (sample rate tuned for cost)

## Threat detection and posture

- GuardDuty enabled organization-wide, all regions, with S3, EKS, Malware Protection, RDS, and Lambda data sources as appropriate
- Security Hub enabled with AWS Foundational Security Best Practices and CIS standards, findings aggregated to the audit account
- IAM Access Analyzer enabled per account; review findings as part of architecture reviews
- Inspector for EC2, ECR, and Lambda vulnerability scanning

## Preventive guardrails (SCPs at OU level)

- Deny root user API actions
- Deny disabling CloudTrail, GuardDuty, Config
- Deny actions in non-approved regions
- Deny creation of IAM users in workload OUs
- Deny public S3 ACLs and BPA disable
- Deny attaching unencrypted EBS volumes

## Encryption

- KMS Customer Managed Keys for sensitive data (control over key policy, rotation, access logs)
- Encryption in transit: TLS everywhere, including internal traffic where feasible (service mesh, ALB-to-target)
- Default-encrypted: RDS, EBS, S3 (account-default on)

## Network ingress

- No `0.0.0.0/0` ingress on instance security groups. Only ALB, CloudFront, or NLB sit on the edge.
- AWS WAF on every public ALB and CloudFront distribution
- AWS Shield Standard included; Shield Advanced for high-value internet-facing workloads

## Secrets

- Secrets Manager for credentials needing rotation; SSM Parameter Store SecureString for static config
- Never bake secrets into AMIs, container images, environment variables in plain text, or repos
