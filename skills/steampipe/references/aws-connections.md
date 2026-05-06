# AWS Connections

The multi-account pattern is the whole reason to use Steampipe. Connections
are HCL blocks in `~/.steampipe/config/aws.spc`. Each connection becomes a
Postgres schema; tables exist inside that schema.

## Single connection (smallest case)

```hcl
connection "aws" {
  plugin  = "aws"
  profile = "default"
  regions = ["us-east-1", "eu-west-1"]
}
```

## Per-account connections

One block per AWS profile, named for the account:

```hcl
connection "aws_prod" {
  plugin  = "aws"
  profile = "prod"
  regions = ["*"]
}

connection "aws_stage" {
  plugin  = "aws"
  profile = "stage"
  regions = ["*"]
}

connection "aws_dev" {
  plugin  = "aws"
  profile = "dev"
  regions = ["us-east-1", "eu-west-1"]
}
```

## Aggregator connection

Query all accounts in a single SELECT. This is the killer feature:

```hcl
connection "aws_all" {
  plugin      = "aws"
  type        = "aggregator"
  connections = ["aws_prod", "aws_stage", "aws_dev"]
}
```

After this, `select * from aws_all.aws_s3_bucket` queries every connection
in parallel. Rows include an `account_id` column to distinguish them.
Wildcards also work: `connections = ["aws_*"]`.

## Authentication

- **SSO profiles** — preferred. Run `aws sso login --profile prod` once per
  session, Steampipe reuses the cached token
- **Assume-role profiles** in `~/.aws/config` with `role_arn` and
  `source_profile` — works transparently
- **EC2 instance profile / ECS task role** — works when running Steampipe
  on AWS
- **IRSA / OIDC** — works inside EKS or GitLab CI with web-identity tokens

Do not put long-lived `access_key`/`secret_key` in `aws.spc`. The file
supports it for local hacking, but it ends up checked into git.

## Typical audit setup

The shape of the multi-account/role hierarchy assumed here matches the
layout in `terragrunt-multi-account` — one audit role per account, assumed
from a central identity account.

```hcl
# ~/.aws/config
[profile audit-org]
sso_session = corp
sso_account_id = 111111111111
sso_role_name  = AuditReadOnly

[profile aws_prod]
source_profile = audit-org
role_arn       = arn:aws:iam::222222222222:role/SecurityAudit

[profile aws_stage]
source_profile = audit-org
role_arn       = arn:aws:iam::333333333333:role/SecurityAudit
```

Then `aws.spc` references each profile by name. One SSO login fans out into
N assume-role chains.

## Cross-cloud configuration

```hcl
# ~/.steampipe/config/github.spc
connection "github" {
  plugin = "github"
  token  = "${GITHUB_TOKEN}"
}
```

```hcl
# ~/.steampipe/config/terraform.spc
connection "terraform" {
  plugin = "terraform"
  paths  = ["/path/to/terraform/**/*.tf"]
}
```

Multiple plugins can be queried in a single SQL statement. Joins happen
Postgres-side after each plugin returns its rows.
