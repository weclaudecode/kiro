# Reliability patterns

Covers retries, pagination, idempotency tokens, and backoff for eventual consistency.

## Retries: standard vs adaptive

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

## Pagination: always

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

## Idempotency tokens

Many create operations accept a client-side idempotency token (`ClientToken`, `ClientRequestToken`). Pass a deterministic UUID derived from the operation's logical identity so a retry of the same operation does not create duplicates.

```python
import uuid

def ensure_run_instance(session: boto3.Session, run_key: str, **params) -> str:
    token = str(uuid.uuid5(uuid.NAMESPACE_OID, f"runinstances:{run_key}"))
    response = session.client("ec2").run_instances(ClientToken=token, **params)
    return response["Instances"][0]["InstanceId"]
```

## Backoff for eventual consistency

botocore retries on transport errors and a fixed set of error codes. It does not retry application-level "the resource I just created is not visible yet" loops. For those, use waiters where they exist; otherwise write explicit backoff.

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

Where waiters exist, prefer them — they are tuned per-API:

```python
ec2 = session.client("ec2")
ec2.run_instances(...)
waiter = ec2.get_waiter("instance_running")
waiter.wait(InstanceIds=[instance_id], WaiterConfig={"Delay": 5, "MaxAttempts": 60})
```
