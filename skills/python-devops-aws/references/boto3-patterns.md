# boto3 patterns

Covers client vs resource, sessions, credential resolution, assume-role, and region handling.

## Client vs resource

boto3 has two interfaces: low-level `client` (one-to-one with API operations, returns dicts) and high-level `resource` (object-oriented). Resource is being deprecated in boto3 v2 and is no longer receiving new service support. Use `client` for new code. If object-oriented ergonomics matter, write thin wrappers around the client.

```python
import boto3

session = boto3.Session(region_name="us-east-1")
s3 = session.client("s3")
response = s3.list_objects_v2(Bucket="my-bucket")
```

## Sessions: never use the module-level client in libraries

`boto3.client("s3")` uses a hidden default session keyed off process-wide state. In a library or any code that may run in a multi-account script, this is a bug — credentials, regions, and config get cross-contaminated. Always accept an explicit `boto3.Session` (or take one as a constructor argument).

```python
# Wrong: implicit default session
import boto3
def list_buckets():
    return boto3.client("s3").list_buckets()

# Right: explicit session
import boto3
def list_buckets(session: boto3.Session) -> list[dict]:
    return session.client("s3").list_buckets()["Buckets"]
```

## Credential resolution order

botocore resolves credentials in this order, stopping at the first match:

1. Explicit `aws_access_key_id` / `aws_secret_access_key` / `aws_session_token` passed to `Session()`
2. Environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
3. Shared credentials file (`~/.aws/credentials`) — selected by `AWS_PROFILE` or `--profile`
4. Shared config file (`~/.aws/config`) — including SSO and `credential_process`
5. Container credentials (ECS task role) via `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`
6. EC2 instance metadata service (IMDSv2)

To debug resolution, set `BOTO_LOG_LEVEL=DEBUG` and inspect `session.get_credentials().method`:

```python
import boto3
session = boto3.Session()
creds = session.get_credentials()
print(creds.method)  # 'iam-role', 'env', 'shared-credentials-file', etc.
```

## Assume role pattern

For cross-account work, call `sts:AssumeRole` and build a new session from the returned temporary credentials. Cache the session per (account, role) pair to avoid hitting STS on every call.

```python
from __future__ import annotations
import boto3
from botocore.config import Config

_DEFAULT_CONFIG = Config(retries={"mode": "standard", "max_attempts": 5})


def get_session_for_account(
    base_session: boto3.Session,
    account_id: str,
    role_name: str,
    region: str,
    session_name: str = "mytool",
) -> boto3.Session:
    """Return a session with credentials assumed into the target account."""
    sts = base_session.client("sts", config=_DEFAULT_CONFIG)
    role_arn = f"arn:aws:iam::{account_id}:role/{role_name}"
    response = sts.assume_role(RoleArn=role_arn, RoleSessionName=session_name)
    creds = response["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        region_name=region,
    )
```

For long-running processes, wrap with refresh logic using `botocore.credentials.RefreshableCredentials.create_from_metadata` or a periodic re-assume. The simple version above is fine for scripts that run for less than the role's max session duration (default 1 hour).

## Region: never default

Never rely on a default region. Different AWS environments (developer laptops, CI, instance metadata) resolve regions differently, and a missing region is one of the most common causes of "the script worked locally but failed in CI." Require region explicitly via CLI flag, environment variable, or config file:

```python
import os
import boto3

def make_session(profile: str | None, region: str | None) -> boto3.Session:
    region = region or os.environ.get("AWS_REGION")
    if not region:
        raise SystemExit("AWS region not set; pass --region or set AWS_REGION")
    return boto3.Session(profile_name=profile, region_name=region)
```

## Type hints

Stock boto3 returns `Any` everywhere, which defeats `mypy --strict`. Install `boto3-stubs` for typed clients. Pick only the services used to keep install size down.

```bash
uv add --dev "boto3-stubs[s3,ec2,sts,iam]"
```

Use the protocol types in annotations:

```python
from __future__ import annotations
from typing import TYPE_CHECKING

import boto3

if TYPE_CHECKING:
    from mypy_boto3_s3.client import S3Client
    from mypy_boto3_s3.type_defs import ObjectTypeDef


def list_all_objects(session: boto3.Session, bucket: str) -> list[ObjectTypeDef]:
    s3: S3Client = session.client("s3")
    paginator = s3.get_paginator("list_objects_v2")
    objects: list[ObjectTypeDef] = []
    for page in paginator.paginate(Bucket=bucket):
        objects.extend(page.get("Contents", []))
    return objects
```

`TYPE_CHECKING` keeps the stubs out of runtime imports — they are only needed by mypy. Run `mypy --strict src/` in CI.
