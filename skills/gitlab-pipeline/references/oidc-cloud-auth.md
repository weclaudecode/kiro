# OIDC Cloud Auth

The single largest pipeline-security upgrade in the last few years is
OIDC federation: GitLab issues a short-lived JWT to the job, the cloud
provider trusts that JWT, and the job assumes a role with no static
credentials anywhere.

## AWS

Trust policy on the IAM role (one-time setup, in IaC — see
`templates/aws-trust-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789012:oidc-provider/gitlab.example.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "gitlab.example.com:aud": "https://gitlab.example.com"
      },
      "StringLike": {
        "gitlab.example.com:sub": "project_path:platform/payments:ref_type:branch:ref:main"
      }
    }
  }]
}
```

The `sub` claim is the important condition. The common shapes are:

- `project_path:GROUP/PROJECT:ref_type:branch:ref:main` — main branch only.
- `project_path:GROUP/PROJECT:ref_type:tag:ref:v*` — release tags.
- `project_path:GROUP/PROJECT:ref_type:branch:ref:*` — any branch (loose).
- `project_path:GROUP/PROJECT:environment:production` — only jobs whose
  `environment.name` is `production`. This is the cleanest pattern for
  multi-environment trust.

Reusable template job (also see `templates/aws-oidc.yml`):

```yaml
.aws-auth:
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: https://gitlab.example.com
  before_script:
    - >
      STS_RESPONSE=$(aws sts assume-role-with-web-identity
        --role-arn "${AWS_ROLE_ARN}"
        --role-session-name "gitlab-${CI_PROJECT_ID}-${CI_JOB_ID}"
        --web-identity-token "${GITLAB_OIDC_TOKEN}"
        --duration-seconds 3600)
    - export AWS_ACCESS_KEY_ID=$(echo "$STS_RESPONSE" | jq -r .Credentials.AccessKeyId)
    - export AWS_SECRET_ACCESS_KEY=$(echo "$STS_RESPONSE" | jq -r .Credentials.SecretAccessKey)
    - export AWS_SESSION_TOKEN=$(echo "$STS_RESPONSE" | jq -r .Credentials.SessionToken)
    - aws sts get-caller-identity
```

Consumers extend it:

```yaml
deploy_dev:
  extends: .aws-auth
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::111111111111:role/gitlab-deploy-dev
  environment: { name: dev }
  script:
    - aws s3 sync ./dist s3://app-dev-static/
```

## GCP

GCP Workload Identity Federation: configure a workload identity pool,
map the `sub` claim to a service account, and call
`gcloud auth login --cred-file=` against a credential config file
written from the OIDC token.

```yaml
.gcp-auth:
  id_tokens:
    GCP_OIDC_TOKEN:
      aud: https://iam.googleapis.com/projects/$GCP_PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER
  before_script:
    - echo "$GCP_OIDC_TOKEN" > /tmp/oidc.token
    - >
      cat > /tmp/cred.json <<EOF
      {
        "type": "external_account",
        "audience": "//iam.googleapis.com/projects/$GCP_PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER",
        "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
        "token_url": "https://sts.googleapis.com/v1/token",
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SA_EMAIL:generateAccessToken",
        "credential_source": { "file": "/tmp/oidc.token" }
      }
      EOF
    - gcloud auth login --cred-file=/tmp/cred.json
```

## Azure

Federated credential on a user-assigned managed identity. Use
`az login --federated-token`:

```yaml
.azure-auth:
  id_tokens:
    AZURE_OIDC_TOKEN:
      aud: api://AzureADTokenExchange
  before_script:
    - >
      az login --service-principal
      --username "$AZURE_CLIENT_ID"
      --tenant "$AZURE_TENANT_ID"
      --federated-token "$AZURE_OIDC_TOKEN"
```

## Variable scopes and flags

Variables can be set at instance, group, or project level. Three flags
matter:

- **Masked**: GitLab masks the value in job logs. Required for any
  secret. The value must satisfy mask rules.
- **Protected**: only exposed to jobs running on protected branches or
  protected tags. Required to prevent a feature branch from exfiltrating
  prod credentials.
- **File**: GitLab writes the value to a temp file and exposes the path
  via the variable. Useful for kubeconfigs, service-account JSON, and
  any multi-line secret.

For a real secret, "masked + protected" is the floor, not a nice-to-have.

## External vault integration

For anything beyond a handful of secrets, integrate with a real secret
store. HashiCorp Vault example using GitLab JWT auth:

```yaml
get_db_password:
  id_tokens:
    VAULT_ID_TOKEN:
      aud: https://vault.example.com
  secrets:
    DB_PASSWORD:
      vault: ops/data/db/prod@kv
      file: false
  script:
    - psql "postgres://app:${DB_PASSWORD}@db.example.com/app"
```

## Never echo secrets

`echo $DB_PASSWORD` for "debugging" is a hard no, even with masking.
Masking is best-effort; it relies on string equality. If a secret is
base64-encoded, JSON-wrapped, or split across lines it leaks in
cleartext.
