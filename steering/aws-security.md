<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: always
---

# AWS Security Defaults

Apply these by default. Deviations require explicit justification in the MR.

## IAM
- **Least privilege.** No `Action: "*"` and no `Resource: "*"` together,
  ever. Scope to the actual ARN(s).
- One role per Lambda. No shared "lambda-execution-role".
- Cross-account access via role assumption + external ID, not user keys.
- Console access is SSO-only (AWS IAM Identity Center). No IAM users.
- Service-linked roles preferred where AWS provides them.

## Encryption
- **At rest:** all S3 buckets `BucketEncryption` with KMS (CMK, not aws/s3).
  All EBS volumes encrypted. RDS storage encrypted. SSM `SecureString` for
  parameters with secrets.
- **In transit:** TLS 1.2+ everywhere. S3 buckets enforce
  `aws:SecureTransport` via bucket policy. ALBs redirect 80→443.
- **Customer-managed KMS keys** with rotation enabled, separate keys per
  data classification (PII vs. non-PII).

## Network
- Lambdas that touch sensitive data run in a VPC with private subnets.
- Lambdas that don't touch private resources stay out of VPCs (cold-start
  cost without benefit).
- Security groups scoped to specific source SGs/CIDRs — no `0.0.0.0/0`
  on anything except a public ALB's `:443`.
- VPC endpoints for `s3`, `dynamodb`, `secretsmanager`, `ssm` to keep
  traffic off the public internet.

## Audit & detection
- CloudTrail multi-region + organization trail, log file validation on,
  delivered to a central log archive account.
- GuardDuty + Security Hub enabled in every account, every region in use.
- AWS Config recording for all supported resources.

## Hard rules
- No public S3 buckets unless they exist to host public web assets and
  have a bucket policy explicitly allowing only `s3:GetObject` on a prefix.
- No security-group rule with `0.0.0.0/0` and a port other than 443.
- No IAM policy with `"NotAction"` or `"NotResource"` without a comment
  explaining why.
