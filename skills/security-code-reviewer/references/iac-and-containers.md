# IaC and Container Review

This reference covers Terraform / CloudFormation / CDK and Dockerfile
findings. The reviewer runs `checkov -d .`, `tfsec`, or `trivy config .`
first; human review then catches business-logic IAM (e.g. a role that
legitimately needs `s3:GetObject` but on the wrong bucket pattern).

## Terraform / CloudFormation / CDK

Common high-impact findings:

- **Public S3 buckets.** Missing `aws_s3_bucket_public_access_block` with
  all four flags `true`; ACL `public-read`; bucket policy `Principal: "*"`.
- **Missing S3 encryption.** No
  `aws_s3_bucket_server_side_encryption_configuration`.
- **Security groups open to the world on non-HTTP ports.** `0.0.0.0/0` on
  22 (SSH), 3389 (RDP), 3306 (MySQL), 5432 (Postgres), 6379 (Redis), 27017
  (Mongo), 9200 (Elasticsearch).
- **IAM wildcards.** `Action: "*"` or `Resource: "*"` on writeable services
  (`s3:*`, `iam:*`, `kms:*`, `lambda:*`). Read-only wildcards are still bad
  for blast radius but worse for mutating actions.
- **RDS/EBS unencrypted.** `storage_encrypted = false` (or omitted on older
  providers).
- **RDS publicly accessible.** `publicly_accessible = true`.
- **Logs disabled.** CloudTrail not enabled in all regions, VPC Flow Logs
  off, S3 access logging off, RDS logs not exported.
- **Lambda Function URL `AuthType: NONE`.** Anyone on the internet can
  invoke. Use IAM auth or front with API Gateway + authorizer.
- **API Gateway without authorizer.** `authorization = "NONE"` on a method
  that calls a sensitive backend.
- **EKS public endpoint.** `endpoint_public_access = true` without
  `public_access_cidrs` restriction.
- **Secrets in Terraform state.** Plaintext secrets in `.tfvars` committed
  to git, or non-encrypted state backend.

```hcl
# Vulnerable
resource "aws_security_group_rule" "ingress" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# Fixed
resource "aws_security_group_rule" "ingress" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.bastion_cidr]
}
```

```hcl
# Vulnerable — public S3 bucket
resource "aws_s3_bucket" "uploads" {
  bucket = "app-uploads"
  acl    = "public-read"
}

# Fixed — block public access, enable SSE
resource "aws_s3_bucket" "uploads" {
  bucket = "app-uploads"
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.uploads.arn
    }
  }
}
```

## Container / Dockerfile Review

- **`USER root`** at the end of the Dockerfile (or no `USER` at all —
  defaults to root). Add a non-root user.
- **`apt-get install` without `--no-install-recommends`** and without a
  `rm -rf /var/lib/apt/lists/*` cleanup — bloats the image and the attack
  surface.
- **Secrets in `ENV` or `ARG`.** `ENV API_KEY=...` is baked into the image;
  anyone with pull access reads it. `ARG` survives in build cache and
  history. Use BuildKit `--mount=type=secret`.
- **Build-time secrets in layers.**
  `RUN curl -H "Authorization: Bearer $TOKEN"` with a `--build-arg TOKEN`
  leaves the token in image history.
- **Base image `:latest`.** Pin to a digest (`@sha256:...`) for
  reproducibility and to prevent supply-chain swaps.
- **No signature verification.** Cosign / sigstore for the base image and
  for produced images.
- **No SBOM.** Generate with `syft` or BuildKit `--sbom=true`; ship with
  the image.
- **`COPY . .` over `COPY --chown` and a `.dockerignore`.** Local secrets
  (`.env`, `.aws/`, `.git/`) end up in the image.

```dockerfile
# Vulnerable
FROM python:latest
COPY . /app
RUN pip install -r requirements.txt
CMD ["python", "app.py"]

# Fixed
FROM python:3.12-slim@sha256:abc123...
RUN useradd --system --uid 1000 app
WORKDIR /app
COPY --chown=app:app requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=app:app . .
USER app
CMD ["python", "app.py"]
```
