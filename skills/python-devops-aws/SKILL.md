---
name: python-devops-aws
description: Use when writing Python scripts, CLI tools, or automation that runs outside Lambda and interacts with AWS via boto3 — covers boto3 client/resource patterns, credentials and assume-role, retries and pagination, error handling, logging, packaging, and testing
---

# Python for DevOps with AWS

## Overview

Production Python for DevOps is explicit, observable, and idempotent. boto3 looks like a generic SDK but has sharp edges — implicit sessions, default retry behavior that hides throttling, list APIs that silently truncate at 1000 items, and credential resolution that varies by execution environment. Code that calls AWS in production must paginate every list, parse `ClientError` codes deliberately, log AWS request IDs, and never rely on the module-level default session. This skill covers stand-alone scripts, CLI tools, automation jobs, and code that runs on EC2, ECS, developer laptops, and CI runners.

## When to Use

Use this skill when:

- Writing a script that calls AWS APIs from a CI runner, EC2 instance, ECS task, or local laptop
- Building a CLI tool that wraps AWS operations (deployments, IAM audits, cost reports, S3 sync)
- Automating IAM, S3, EC2, RDS, or other AWS resources from a runner
- Writing one-off remediation scripts that need to be safe and re-runnable
- Creating shared platform tooling distributed to multiple engineers
- Building data-pipeline glue that orchestrates AWS services from a long-running process

**When NOT to use:** for AWS Lambda handler code, see the `python-lambda` skill. Lambda has a different cold-start, packaging, and credential model that is covered there.

## Python project structure

A reproducible Python project uses PEP 621 metadata in `pyproject.toml`, a lockfile (uv, pip-tools, or Poetry), and the src layout. `requirements.txt` alone is not enough: it pins direct deps but not transitive ones, and it doesn't capture build-time metadata or entry points. A lockfile guarantees the same dep tree on every machine and CI run.

The src layout (`src/mytool/`) prevents accidental imports from the working directory and forces tests to import from the installed package, catching missing-package-data bugs early.

```toml
# pyproject.toml
[project]
name = "mytool"
version = "0.3.0"
description = "Internal AWS automation CLI"
requires-python = ">=3.11"
dependencies = [
    "boto3>=1.34",
    "botocore>=1.34",
    "typer>=0.12",
    "structlog>=24.1",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov>=5.0",
    "moto[all]>=5.0",
    "mypy>=1.10",
    "boto3-stubs[s3,ec2,sts,iam]>=1.34",
    "ruff>=0.5",
]

[project.scripts]
mytool = "mytool.cli:app"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/mytool"]

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "S", "N", "RET", "SIM"]

[tool.mypy]
strict = true
python_version = "3.11"
plugins = []
```

Layout:

```
mytool/
  pyproject.toml
  uv.lock
  src/mytool/
    __init__.py
    __main__.py
    cli.py
    aws/
      __init__.py
      session.py
      s3.py
  tests/
    test_session.py
    test_s3.py
```

Use `uv sync` to install from the lockfile, `uv lock --upgrade` to refresh it. Commit `uv.lock` (or `requirements.lock`) to the repo.

## boto3 essentials

### Client vs resource

boto3 has two interfaces: low-level `client` (one-to-one with API operations, returns dicts) and high-level `resource` (object-oriented). Resource is being deprecated in boto3 v2 and is no longer receiving new service support. Use `client` for new code. If object-oriented ergonomics matter, write thin wrappers around the client.

```python
import boto3

session = boto3.Session(region_name="us-east-1")
s3 = session.client("s3")
response = s3.list_objects_v2(Bucket="my-bucket")
```

### Sessions: never use the module-level client in libraries

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

### Credential resolution order

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

### Assume role pattern

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

### Region: never default

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

## Reliability patterns

### Retries: standard vs adaptive

botocore has three retry modes:

- `legacy` (default in old versions) — retries 4 times, no jitter
- `standard` — retries 3 times by default, exponential backoff with jitter, retries on additional error codes
- `adaptive` — adds client-side rate limiting that learns from throttle responses

Use `standard` as a baseline. Use `adaptive` when calling APIs with low TPS limits (IAM, Organizations, billing) or when running many parallel callers. Override `max_attempts` for long-running automation that can tolerate longer waits.

```python
from botocore.config import Config

retry_config = Config(
    retries={"mode": "adaptive", "max_attempts": 10},
    connect_timeout=5,
    read_timeout=30,
)
client = session.client("iam", config=retry_config)
```

### Pagination: always

List/describe APIs return at most 1000 items per call (often less). Single-call code that "works in dev" silently truncates in prod. Always use `get_paginator`. The result is iterable and handles `NextToken`/`Marker` automatically.

```python
def list_all_objects(session: boto3.Session, bucket: str, prefix: str = "") -> list[dict]:
    s3 = session.client("s3")
    paginator = s3.get_paginator("list_objects_v2")
    objects: list[dict] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        objects.extend(page.get("Contents", []))
    return objects


def list_all_running_instances(session: boto3.Session) -> list[dict]:
    ec2 = session.client("ec2")
    paginator = ec2.get_paginator("describe_instances")
    instances: list[dict] = []
    for page in paginator.paginate(
        Filters=[{"Name": "instance-state-name", "Values": ["running"]}],
    ):
        for reservation in page["Reservations"]:
            instances.extend(reservation["Instances"])
    return instances
```

For large result sets, prefer streaming over collecting into a list:

```python
def iter_all_objects(session: boto3.Session, bucket: str, prefix: str = ""):
    paginator = session.client("s3").get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        yield from page.get("Contents", [])
```

### Idempotency tokens

Many create operations accept a client-side idempotency token (`ClientToken`, `ClientRequestToken`). Pass a deterministic UUID derived from the operation's logical identity so a retry of the same operation doesn't create duplicates.

```python
import uuid

def ensure_run_instance(session: boto3.Session, run_key: str, **params) -> str:
    token = str(uuid.uuid5(uuid.NAMESPACE_OID, f"runinstances:{run_key}"))
    response = session.client("ec2").run_instances(ClientToken=token, **params)
    return response["Instances"][0]["InstanceId"]
```

### Backoff for eventual consistency

botocore retries on transport errors and a fixed set of error codes. It does not retry your application-level "the resource I just created isn't visible yet" loops. For those, use waiters where they exist; otherwise write explicit backoff.

```python
import random
import time
from collections.abc import Callable
from typing import TypeVar

T = TypeVar("T")


def retry_with_backoff(
    fn: Callable[[], T],
    *,
    is_retryable: Callable[[Exception], bool],
    max_attempts: int = 6,
    base_delay: float = 0.5,
    max_delay: float = 30.0,
) -> T:
    """Call fn() with full-jitter exponential backoff on retryable exceptions."""
    last_exc: Exception | None = None
    for attempt in range(max_attempts):
        try:
            return fn()
        except Exception as exc:
            if not is_retryable(exc):
                raise
            last_exc = exc
            delay = min(max_delay, base_delay * (2**attempt))
            time.sleep(random.uniform(0, delay))
    assert last_exc is not None
    raise last_exc
```

Where waiters exist, prefer them — they're tuned per-API:

```python
ec2 = session.client("ec2")
ec2.run_instances(...)
waiter = ec2.get_waiter("instance_running")
waiter.wait(InstanceIds=[instance_id], WaiterConfig={"Delay": 5, "MaxAttempts": 60})
```

## Error handling

Every boto3 API call can raise `botocore.exceptions.ClientError`. The error code lives in `e.response["Error"]["Code"]` and is the only stable identifier — error messages change. Never catch bare `Exception`; catch `ClientError` and dispatch on the code.

```python
from botocore.exceptions import ClientError


class ResourceNotFound(Exception):
    pass


class AccessDenied(Exception):
    pass


class Throttled(Exception):
    pass


def get_bucket_tagging(session: boto3.Session, bucket: str) -> dict[str, str]:
    s3 = session.client("s3")
    try:
        response = s3.get_bucket_tagging(Bucket=bucket)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        match code:
            case "NoSuchTagSet" | "NoSuchBucket":
                raise ResourceNotFound(bucket) from exc
            case "AccessDenied" | "AccessDeniedException":
                raise AccessDenied(bucket) from exc
            case "ThrottlingException" | "RequestLimitExceeded":
                raise Throttled(code) from exc
            case _:
                raise
    return {t["Key"]: t["Value"] for t in response["TagSet"]}
```

Codes worth handling explicitly across most services:

- `ThrottlingException`, `Throttling`, `RequestLimitExceeded`, `TooManyRequestsException`
- `ResourceNotFoundException`, `NoSuchEntity`, `NoSuchBucket`, `NoSuchKey`
- `AccessDenied`, `AccessDeniedException`, `UnauthorizedOperation`
- `ValidationException`, `InvalidParameterValue`
- `ConditionalCheckFailedException` (DynamoDB)
- `ResourceInUseException`, `ResourceConflictException`

For decorator ergonomics:

```python
from functools import wraps


def translate_client_errors(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code in {"AccessDenied", "AccessDeniedException"}:
                raise AccessDenied(str(exc)) from exc
            if code in {"ThrottlingException", "Throttling"}:
                raise Throttled(str(exc)) from exc
            raise
    return wrapper
```

## Logging and observability

Never use `print` in scripts that run unattended. Use structured JSON logging so logs can be queried in CloudWatch Logs Insights, Datadog, or any log aggregator. Always include the AWS request ID from `response["ResponseMetadata"]["RequestId"]` — this is what AWS Support asks for first.

```python
import logging
import sys

import structlog


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=level,
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    )


log = structlog.get_logger()


def delete_object(session: boto3.Session, bucket: str, key: str) -> None:
    s3 = session.client("s3")
    response = s3.delete_object(Bucket=bucket, Key=key)
    log.info(
        "s3.delete_object",
        bucket=bucket,
        key=key,
        request_id=response["ResponseMetadata"]["RequestId"],
        version_id=response.get("VersionId"),
    )
```

When logging errors:

```python
except ClientError as exc:
    log.error(
        "s3.delete_object.failed",
        bucket=bucket,
        key=key,
        error_code=exc.response["Error"]["Code"],
        request_id=exc.response.get("ResponseMetadata", {}).get("RequestId"),
        exc_info=True,
    )
    raise
```

Never log full request/response bodies blindly — they may contain credentials, signed URLs, or PII. Whitelist fields.

## CLI ergonomics

Use Typer for type-hint-driven CLIs. It's built on Click, parses type annotations into argument types, and produces good `--help` output without ceremony. Always provide `--profile`, `--region`, `--dry-run`, and `--yes` for destructive operations. Default to dry-run.

```python
from __future__ import annotations
from typing import Annotated

import boto3
import typer

from mytool.aws.session import make_session
from mytool.logging import configure_logging, log

app = typer.Typer(no_args_is_help=True, add_completion=False)


@app.command()
def delete_old_snapshots(
    older_than_days: Annotated[int, typer.Option(min=1)] = 30,
    profile: Annotated[str | None, typer.Option(help="AWS profile")] = None,
    region: Annotated[str | None, typer.Option(envvar="AWS_REGION")] = None,
    dry_run: Annotated[bool, typer.Option(help="Plan without deleting")] = True,
    yes: Annotated[bool, typer.Option(help="Skip confirmation")] = False,
    log_level: Annotated[str, typer.Option()] = "INFO",
) -> None:
    """Delete EBS snapshots older than N days."""
    configure_logging(log_level)
    session = make_session(profile=profile, region=region)
    snapshots = find_old_snapshots(session, older_than_days)
    log.info("snapshots.found", count=len(snapshots), dry_run=dry_run)

    if dry_run:
        for snap in snapshots:
            log.info("snapshots.would_delete", snapshot_id=snap["SnapshotId"])
        return

    if not yes:
        typer.confirm(f"Delete {len(snapshots)} snapshots?", abort=True)

    for snap in snapshots:
        delete_snapshot(session, snap["SnapshotId"])


if __name__ == "__main__":
    app()
```

Default `dry_run=True` means a user who runs the command without flags gets a plan, not a destructive action. They have to opt in with `--no-dry-run --yes`.

## Testing

Use `moto` for unit tests of code that calls AWS. moto patches boto3 to talk to an in-memory mock of the service. Use `botocore.stub.Stubber` for tighter control or services moto doesn't cover well.

### moto with pytest fixtures

```python
# tests/test_s3.py
import boto3
import pytest
from moto import mock_aws

from mytool.aws.s3 import list_all_objects


@pytest.fixture
def aws_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    """Set fake credentials so boto3 doesn't hit a real account in tests."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


@pytest.fixture
def session(aws_credentials: None):
    with mock_aws():
        yield boto3.Session(region_name="us-east-1")


def test_list_all_objects_returns_all_pages(session: boto3.Session) -> None:
    s3 = session.client("s3")
    s3.create_bucket(Bucket="test-bucket")
    for i in range(2500):
        s3.put_object(Bucket="test-bucket", Key=f"prefix/obj-{i:05d}", Body=b"x")

    result = list_all_objects(session, "test-bucket", prefix="prefix/")

    assert len(result) == 2500
    assert all(obj["Key"].startswith("prefix/") for obj in result)
```

### Stubber for precise responses

When testing error paths or services with complex responses, use Stubber:

```python
from botocore.stub import Stubber


def test_get_bucket_tagging_handles_no_tag_set() -> None:
    session = boto3.Session(region_name="us-east-1")
    client = session.client("s3")
    with Stubber(client) as stub:
        stub.add_client_error(
            "get_bucket_tagging",
            service_error_code="NoSuchTagSet",
            expected_params={"Bucket": "b"},
        )
        # Inject the stubbed client into your code under test
        with pytest.raises(ResourceNotFound):
            get_bucket_tagging_with_client(client, "b")
```

Use moto for behavior tests (multiple calls, pagination, eventual consistency). Use Stubber for error-path tests where you need exact control.

## Type hints

Stock boto3 returns `Any` everywhere, which defeats `mypy --strict`. Install `boto3-stubs` for typed clients. Pick only the services you use to keep install size down.

```bash
uv add --dev "boto3-stubs[s3,ec2,sts,iam]"
```

Then use the protocol types in annotations:

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

`TYPE_CHECKING` keeps the stubs out of runtime imports — they're only needed by mypy. Run `mypy --strict src/` in CI.

## Packaging and execution

Distribute shared tools as installable packages. Avoid the temptation of "just chmod +x and copy the file" — it bypasses dependency management and breaks the moment someone has a different boto3 version.

Three good execution paths:

1. **Module execution:** `python -m mytool` works once the package is installed. Add `src/mytool/__main__.py` that calls `from mytool.cli import app; app()`.
2. **Entry-point script:** the `[project.scripts]` table in `pyproject.toml` creates a `mytool` console script on install. After `uv pip install .` or `uv tool install .`, users run `mytool ...`.
3. **uv tool / uvx:** `uv tool install .` installs into an isolated venv. `uvx --from . mytool` runs without installing globally.

For internal sharing, publish to a private package index (CodeArtifact, GitHub Packages, internal PyPI) and let users `uv tool install mytool`. For one-off scripts in a repo, `uv run mytool/script.py` is fine — uv resolves deps from `pyproject.toml` automatically.

Shebangs (`#!/usr/bin/env python3`) and `chmod +x` work for personal scripts but fail for shared tools because:

- They depend on whatever Python and packages are on `$PATH`
- They have no way to declare or verify dependency versions
- They break when run from a different working directory
- They can't be tested in isolation

## Common Mistakes

| Mistake | Why it bites | Fix |
|---|---|---|
| Using the default `boto3.client(...)` in a multi-account script | Hidden process-wide state crosses credentials between accounts | Pass `boto3.Session` explicitly into every function |
| Calling `list_objects_v2` / `describe_*` once and trusting the result | Silently truncates at 1000 items in production | Use `client.get_paginator(...).paginate(...)` always |
| Catching `Exception` around a boto3 call | Swallows code bugs and AWS errors alike, hides the error code | Catch `ClientError` and match on `e.response["Error"]["Code"]` |
| Hard-coding `region_name="us-east-1"` | Script runs in the wrong region in another account or CI environment | Require `--region` or `AWS_REGION` env var, fail loud if missing |
| `time.sleep(30)` while waiting for a resource | Brittle, slow, fails under load | Use built-in waiters; for custom waits, exponential backoff with jitter |
| Logging `event` or full API response | Leaks credentials, signed URLs, PII into logs | Whitelist fields; always log `RequestId`, never raw responses |
| `def helper(items: list = []):` | Mutable default shared across calls causes phantom data | Use `items: list | None = None` and assign inside the function |
| `boto3.resource("s3")` for new code | Resource interface is being deprecated in boto3 v2 | Use `client` and write thin wrappers if you need OO ergonomics |
| Running scripts as `chmod +x foo.py` from random checkouts | No dep pinning, no reproducibility, version drift | Package as a project, install with `uv tool install .`, run via entry point |
| `print()` for status output in unattended jobs | Can't filter by level, no structure, breaks when piped | structlog + JSON renderer; `print` only for interactive CLI output |

## Quick Reference

| Helper | Purpose |
|---|---|
| `make_session(profile, region)` | Build an explicit `boto3.Session` with required region |
| `get_session_for_account(base, account_id, role, region)` | Assume role across accounts and return a usable session |
| `list_all(client, op, key, **kwargs)` | Generic paginate-and-collect for any list/describe operation |
| `iter_all(client, op, key, **kwargs)` | Streaming version of the above for large result sets |
| `retry_with_backoff(fn, is_retryable, ...)` | Application-level full-jitter exponential backoff |
| `translate_client_errors` decorator | Convert `ClientError` codes into typed domain exceptions |
| `configure_logging(level)` | Set up structlog JSON output with timestamps and levels |
| `Config(retries={"mode": "adaptive", "max_attempts": N})` | Override botocore retry behavior per-client |
| `client.get_paginator(op).paginate(**params)` | Standard pagination — never call list operations without this |
| `client.get_waiter(name).wait(...)` | Built-in polling for resource state transitions |
| `Stubber(client).add_response / add_client_error` | Precise unit-test stubs for boto3 calls |
| `mock_aws()` from moto | In-memory AWS mock for behavior tests |
| `boto3-stubs[service,...]` | Typed clients for `mypy --strict` compliance |
