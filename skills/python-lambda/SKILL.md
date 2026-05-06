---
name: python-lambda
description: Use when writing Python AWS Lambda handlers — covers handler structure, cold start optimization, AWS Lambda Powertools, Parameter Store/Secrets Manager, environment variables, error handling and DLQs, packaging with layers or container images, and local testing
---

# Python for AWS Lambda

## Overview

AWS Lambda is a constrained, ephemeral runtime. The patterns that work well for long-running services — eager imports, deep connection pools, request-scoped client construction, in-process caches refreshed on a thread — actively hurt a Lambda function. Containers freeze between invocations, can be reaped at any time, have a hard memory ceiling, and bill by the millisecond. This skill covers the patterns that distinguish a Lambda that survives production from one that quietly burns money, times out under load, or poisons its own queue.

For general boto3 client construction, retry/backoff configuration, pagination, and Python-on-AWS scripting patterns, see the companion `python-devops-aws` skill. This document assumes those patterns and only covers what is Lambda-specific.

## When to Use

Use this skill when:

- Writing a new Python Lambda handler from scratch
- Modifying an existing handler (adding an event source, changing the response shape, adding retries)
- Debugging cold start latency, timeouts, or memory pressure
- Wiring an event-driven handler to S3, SQS, SNS, EventBridge, Kinesis, DynamoDB Streams, or API Gateway
- Choosing between zip, layer, or container image packaging
- Adding observability (Powertools Logger, Tracer, Metrics) to a Lambda

Do not use this skill for general Python+AWS scripts that run on EC2, ECS, or a developer laptop — use the `python-devops-aws` skill instead. Do not use it for non-Python runtimes (Node.js, Go, Java) — the constraints overlap but the import-cost and Powertools details differ.

## Handler structure

The canonical Lambda entry point is a single function that takes two positional arguments:

```python
def handler(event: dict, context: "LambdaContext") -> dict:
    ...
```

The runtime imports the module once per execution environment and calls `handler` once per invocation. Anything at module scope runs during the cold start; anything inside the function runs on every invocation.

### What is in `context`

The `context` object exposes runtime metadata. The fields used most often:

- `context.aws_request_id` — unique per invocation, the right value to put in every log line and downstream call
- `context.function_name`, `context.function_version`, `context.invoked_function_arn`
- `context.memory_limit_in_mb` — configured memory, useful for self-tuning batch sizes
- `context.get_remaining_time_in_millis()` — milliseconds left before the runtime kills the invocation; check it before starting any operation that might exceed the budget
- `context.log_group_name`, `context.log_stream_name` — for cross-referencing in CloudWatch

### Module-level vs handler-level state

Initialize anything reusable at module scope. Do per-request work inside the handler.

Wrong:

```python
import boto3

def handler(event, context):
    s3 = boto3.client("s3")  # rebuilt on every invocation; 50-200ms wasted
    obj = s3.get_object(Bucket=event["bucket"], Key=event["key"])
    return {"size": obj["ContentLength"]}
```

Right:

```python
import boto3

S3 = boto3.client("s3")  # constructed once per execution environment

def handler(event, context):
    obj = S3.get_object(Bucket=event["bucket"], Key=event["key"])
    return {"size": obj["ContentLength"]}
```

The same rule applies to database connection pools, HTTP sessions (`requests.Session`, `httpx.Client`), parsed config, ML model artifacts, and Powertools singletons.

### Why `if __name__ == "__main__"` is irrelevant

Lambda imports the handler module by name (`app.handler` from the function configuration). The module is never run as `__main__`. A `__main__` guard is harmless but does nothing useful in deployed code. Keep `__main__` blocks only for local-test scaffolding that should not run in Lambda.

### Returning a response

The shape of the return value depends on the event source. Mismatched return shapes are a common source of silent failures.

API Gateway (REST or HTTP API, proxy integration):

```python
import json

def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"ok": True}),
        "isBase64Encoded": False,
    }
```

SQS partial batch failure (the only correct way to handle a poison message in a batch):

```python
def handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            process(record)
        except Exception:
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
```

Direct invocation (`Invoke` API, Step Functions, another Lambda) — return any JSON-serializable value. Step Functions in particular reads the raw return value as the next state's input.

## Cold start optimization

Cold starts have two phases: the runtime boot and the user-code initialization. User-code init is usually the dominant cost and the only one engineers control.

### Lazy imports for heavy SDKs

Top-level imports run on every cold start, even if the code path that needs them is rare. Move heavy imports inside the function that uses them.

```python
def handler(event, context):
    if event.get("mode") == "report":
        import pandas as pd  # only paid for on report invocations
        return build_report(pd, event)
    return fast_path(event)
```

`import json`, `import os`, `import datetime` cost essentially nothing. `import pandas` is 300-700ms. `import numpy` alone is 100-200ms. `import boto3` is 200-400ms but unavoidable. Profile with `python -X importtime -c "import your_module" 2> imports.txt`.

### Init at module scope

Cold-start work pays off across all warm invocations on the same execution environment. Good candidates for module-scope initialization:

- `boto3.client(...)` and `boto3.resource(...)`
- HTTP session objects with connection pooling
- Configuration fetched from SSM Parameter Store or Secrets Manager
- Compiled regular expressions
- Pydantic models, JSON schemas
- Powertools `Logger`, `Tracer`, `Metrics` instances

### SnapStart

SnapStart for Python Lambda is generally available on Python 3.12 and 3.13 runtimes (announced late 2024). It snapshots the initialized execution environment after `init` and restores from the snapshot on cold start, eliminating most user-code init cost. Tradeoffs: incompatible with provisioned concurrency on the same alias, requires versioned function aliases, and any module-level state that bakes in time-sensitive values (request signers, short-lived tokens) needs a runtime hook to refresh on restore.

### Provisioned concurrency tradeoffs

Provisioned concurrency keeps N execution environments warm and pre-initialized. Use it for low-latency synchronous APIs where p99 cold-start latency is unacceptable. Costs continue 24/7 whether traffic arrives or not — autoscale provisioned concurrency on a schedule for predictable diurnal traffic.

### Avoid `boto3.client()` per invocation

Creating a client is not free. It loads service models, parses endpoint config, and builds a session. On a 128MB function this is 50-200ms per call. Always hoist clients to module scope.

### Why import discipline matters

A 600ms import-time cost on a 200ms-of-actual-work function turns p50 cold-start latency from 800ms into 1.4s and inflates the GB-second bill by 4x for cold invocations. Treat top-level imports as a budget, not a free list.

## AWS Lambda Powertools for Python

Powertools (v3) is the canonical way to do logging, tracing, metrics, parsing, and idempotency on Python Lambda. It is maintained by AWS, integrates with X-Ray, CloudWatch EMF, and standard event sources, and replaces a pile of bespoke utilities.

Install with the extras the function actually needs:

```
aws-lambda-powertools[tracer,parser,validation]
```

### Logger with `inject_lambda_context`

```python
from aws_lambda_powertools import Logger

logger = Logger(service="orders")

@logger.inject_lambda_context(correlation_id_path="requestContext.requestId")
def handler(event, context):
    logger.info("processing order", extra={"order_id": event["orderId"]})
    return {"ok": True}
```

`inject_lambda_context` adds `function_name`, `function_arn`, `function_request_id`, `cold_start`, and the correlation id to every log line as structured JSON.

### Tracer with `@tracer.capture_method`

```python
from aws_lambda_powertools import Tracer

tracer = Tracer(service="orders")

@tracer.capture_method
def fetch_order(order_id: str) -> dict:
    return DDB.get_item(TableName="orders", Key={"id": {"S": order_id}})["Item"]

@tracer.capture_lambda_handler
def handler(event, context):
    return fetch_order(event["orderId"])
```

`Tracer` wraps boto3 calls and decorated methods as X-Ray subsegments. Enable active tracing on the function for the trace to propagate.

### Metrics with EMF

CloudWatch Embedded Metric Format emits metrics as structured log lines. No extra API calls, no PutMetricData latency, no per-call cost — Lambda already pays for the log ingestion.

```python
from aws_lambda_powertools import Metrics
from aws_lambda_powertools.metrics import MetricUnit

metrics = Metrics(namespace="Orders", service="checkout")

@metrics.log_metrics(capture_cold_start_metric=True)
def handler(event, context):
    metrics.add_metric(name="OrdersProcessed", unit=MetricUnit.Count, value=1)
    metrics.add_dimension(name="region", value=event["region"])
    return {"ok": True}
```

### `event_parser` with Pydantic

Type-safe event handling pays for itself the first time an upstream system sends an unexpected payload.

```python
from aws_lambda_powertools.utilities.parser import event_parser, BaseModel
from aws_lambda_powertools.utilities.parser.models import SqsModel

class OrderBody(BaseModel):
    order_id: str
    amount_cents: int

@event_parser(model=SqsModel)
def handler(event: SqsModel, context):
    for record in event.Records:
        body = OrderBody.model_validate_json(record.body)
        process(body)
```

### `idempotency` decorator

Lambda's at-least-once delivery means handlers must tolerate duplicates. The idempotency utility persists a hash of the event in DynamoDB and short-circuits duplicates.

```python
from aws_lambda_powertools.utilities.idempotency import (
    DynamoDBPersistenceLayer,
    IdempotencyConfig,
    idempotent,
)

persistence = DynamoDBPersistenceLayer(table_name="idempotency")
config = IdempotencyConfig(event_key_jmespath="orderId", expires_after_seconds=3600)

@idempotent(persistence_store=persistence, config=config)
def handler(event, context):
    charge_card(event)
    return {"ok": True}
```

The DynamoDB table needs a partition key named `id` (string) and TTL enabled on an attribute named `expiration`.

### Full example combining all of the above

```python
from aws_lambda_powertools import Logger, Metrics, Tracer
from aws_lambda_powertools.metrics import MetricUnit
from aws_lambda_powertools.utilities.idempotency import (
    DynamoDBPersistenceLayer,
    IdempotencyConfig,
    idempotent,
)
from aws_lambda_powertools.utilities.parser import BaseModel, event_parser
from aws_lambda_powertools.utilities.typing import LambdaContext

logger = Logger(service="orders")
tracer = Tracer(service="orders")
metrics = Metrics(namespace="Orders", service="orders")

persistence = DynamoDBPersistenceLayer(table_name="orders-idempotency")
idem_config = IdempotencyConfig(
    event_key_jmespath="order_id", expires_after_seconds=3600
)


class OrderEvent(BaseModel):
    order_id: str
    amount_cents: int
    customer_id: str


@tracer.capture_method
def charge(order: OrderEvent) -> str:
    logger.info("charging", extra={"order_id": order.order_id})
    return f"ch_{order.order_id}"


@idempotent(persistence_store=persistence, config=idem_config)
@logger.inject_lambda_context(correlation_id_path="order_id")
@tracer.capture_lambda_handler
@metrics.log_metrics(capture_cold_start_metric=True)
@event_parser(model=OrderEvent)
def handler(event: OrderEvent, context: LambdaContext) -> dict:
    charge_id = charge(event)
    metrics.add_metric(name="OrderCharged", unit=MetricUnit.Count, value=1)
    return {"order_id": event.order_id, "charge_id": charge_id}
```

Decorator order matters: `idempotent` outermost (so duplicate suppression happens before logging/tracing fires for a no-op), `event_parser` innermost (so the handler receives the parsed type).

## Configuration and secrets

Environment variables are visible in plain text in the Lambda console to anyone with `lambda:GetFunctionConfiguration`. Use them for non-sensitive config only.

For sensitive values, use Secrets Manager. For shared, less-sensitive config, use SSM Parameter Store. Powertools provides cached helpers that handle TTL and avoid hammering SSM on every invocation.

```
pip install "aws-lambda-powertools[parameters]"
```

```python
from aws_lambda_powertools.utilities import parameters

# SSM Parameter Store, cached for 5 minutes
db_host = parameters.get_parameter("/prod/orders/db-host", max_age=300)

# SSM SecureString
api_key = parameters.get_parameter(
    "/prod/orders/upstream-api-key", decrypt=True, max_age=300
)

# Secrets Manager
creds = parameters.get_secret("prod/orders/db-credentials", max_age=300)
```

Fetch config at module scope when the values are stable across invocations:

```python
from aws_lambda_powertools.utilities import parameters

CONFIG = {
    "db_host": parameters.get_parameter("/prod/orders/db-host", max_age=300),
    "queue_url": parameters.get_parameter("/prod/orders/queue-url", max_age=300),
}

def handler(event, context):
    ...
```

Never embed secrets in environment variables. Never log the contents of `event` if it might carry credentials, PII, or payment data.

## Error handling and retries

Lambda's invocation model determines what happens when a handler raises.

### Synchronous (API Gateway, ALB, direct Invoke with `RequestResponse`)

The exception is returned to the caller as an unhandled error. There is no automatic retry. The handler should catch expected errors and return a structured error response; only let truly unexpected exceptions propagate.

```python
def handler(event, context):
    try:
        result = do_work(event)
    except ValidationError as e:
        return {"statusCode": 400, "body": json.dumps({"error": str(e)})}
    return {"statusCode": 200, "body": json.dumps(result)}
```

### Asynchronous (S3, SNS, EventBridge, async Invoke)

Lambda retries failed async invocations twice (3 attempts total) by default with exponential backoff. After exhausting retries, the event is sent to the configured DLQ or on-failure destination, or dropped silently if neither is configured. Configure a DLQ (SQS or SNS) or, preferably, an EventBridge on-failure destination, on every async-invoked Lambda.

### Stream and queue (SQS, Kinesis, DynamoDB Streams)

The Lambda service polls the source and invokes the handler with a batch. If the handler raises, the entire batch is retried — so one poison message can block a queue or stream forever. Always return partial-batch failures explicitly:

```python
def handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            process(record)
        except Exception:
            logger.exception("record failed", extra={"message_id": record["messageId"]})
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
```

Configure `ReportBatchItemFailures` on the event source mapping for SQS, and a redrive policy on the source queue pointing at a DLQ. For Kinesis and DynamoDB Streams, set `BisectBatchOnFunctionError` and `MaximumRetryAttempts`, and configure an on-failure destination.

### When to raise vs catch-and-return

Raise when the entire invocation is a failure that needs DLQ/retry semantics. Catch and return a structured error when the failure is per-item or per-request and downstream consumers expect a normal response shape.

### Detecting timeout before it kills you

Lambda kills the invocation at the configured timeout. The runtime sends `SIGTERM` then `SIGKILL` — there is no exception to catch. Check `context.get_remaining_time_in_millis()` before starting any operation that could exceed the budget:

```python
def handler(event, context):
    for record in event["Records"]:
        if context.get_remaining_time_in_millis() < 5000:
            logger.warning("near timeout, returning remaining records as failures")
            return {"batchItemFailures": [
                {"itemIdentifier": r["messageId"]}
                for r in remaining_records
            ]}
        process(record)
```

## Packaging

Three options, in increasing order of size and cold-start cost.

### Zip with `requirements.txt`

The simplest option. Install dependencies into a directory, zip it with the handler, upload. The deployment package limit is 50 MB zipped, 250 MB unzipped (including any layers).

```
pip install --target ./package --platform manylinux2014_x86_64 \
    --only-binary=:all: --python-version 3.12 -r requirements.txt
cp app.py ./package/
( cd package && zip -r ../function.zip . )
```

The `--platform manylinux2014_x86_64` flag is critical when building on macOS or Windows — it forces pip to download Linux wheels instead of building from source for the local platform. For ARM Lambdas use `manylinux2014_aarch64`.

### Layers

A layer is a separately versioned zip mounted at `/opt` at runtime. Use layers to share heavy dependencies (boto3 patches, ORM, ML libraries) across multiple functions.

```
mkdir -p layer/python
pip install --target ./layer/python --platform manylinux2014_x86_64 \
    --only-binary=:all: --python-version 3.12 -r layer-requirements.txt
( cd layer && zip -r ../layer.zip python )
aws lambda publish-layer-version --layer-name shared-deps --zip-file fileb://layer.zip
```

Layers count against the 250 MB unzipped limit. A function may attach up to 5 layers. Layer versions are immutable; bumping a dep means publishing a new version and updating the function.

### Container images

Up to 10 GB image size, custom runtimes, full control over the OS layer. Cold starts are slower than zip (typically 1-3s extra on first init), but Lambda caches frequently-used layers across invocations.

```dockerfile
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt .
RUN pip install -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

COPY app.py ${LAMBDA_TASK_ROOT}

CMD ["app.handler"]
```

Build, push to ECR, and configure the function to use the image URI. Use container images when dependencies exceed the 250 MB layer limit, when a custom system library is needed, or when the same image is used in both Lambda and a non-Lambda runtime (ECS, local development).

For SAM users, `sam build --use-container` runs the build inside the official Lambda build image and produces correct Linux wheels regardless of the host OS.

## Local testing

The primary local-testing strategy is `pytest` against the imported handler. Lambda's invocation model is simple enough that a function call with a fake `event` and `context` covers the vast majority of behavior.

```python
# tests/test_handler.py
from dataclasses import dataclass
from unittest.mock import patch

from app import handler


@dataclass
class FakeContext:
    aws_request_id: str = "test-req-1"
    function_name: str = "orders"
    function_version: str = "$LATEST"
    invoked_function_arn: str = "arn:aws:lambda:us-east-1:0:function:orders"
    memory_limit_in_mb: int = 512
    log_group_name: str = "/aws/lambda/orders"
    log_stream_name: str = "stream"

    def get_remaining_time_in_millis(self) -> int:
        return 30_000


def test_handler_returns_200_for_valid_order():
    event = {"order_id": "abc", "amount_cents": 1000, "customer_id": "c1"}
    with patch("app.charge", return_value="ch_abc"):
        result = handler(event, FakeContext())
    assert result["charge_id"] == "ch_abc"
```

Use `moto` to fake AWS service calls — see the `python-devops-aws` skill for boto3 mocking patterns. For Powertools, the library has built-in test helpers; in particular, set `POWERTOOLS_DEV=true` to make the logger emit human-readable output during tests.

`sam local invoke` runs the handler in a Docker container that mirrors the Lambda runtime. Useful for end-to-end smoke tests against a real binary, but slower than pytest and not a substitute for unit tests. The `aws-lambda-runtime-interface-emulator` is the underlying piece — it runs inside the container image and lets `curl` simulate an invocation.

## Performance and cost levers

Lambda allocates CPU proportional to memory: doubling memory roughly doubles CPU. A function that runs in 5s at 512 MB may run in 1s at 2048 MB and cost less in total GB-seconds. Use [AWS Lambda Power Tuning](https://github.com/alexcasalboni/aws-lambda-power-tuning) to find the cost-optimal memory setting for a given workload. Re-tune after significant code changes.

ARM (Graviton) is roughly 20% cheaper per GB-second than x86, and on most Python workloads performs equivalently or slightly better. Build with `--platform manylinux2014_aarch64` and set the function architecture to `arm64`.

Ephemeral storage (`/tmp`) defaults to 512 MB and can be raised to 10 GB. Pay only when actually needed — large temp files for video transcoding, ML model downloads, scratch space for large CSV processing.

Reserved concurrency caps the maximum simultaneous executions of a function and protects downstream systems from being overrun during a Lambda traffic spike. Provisioned concurrency keeps environments pre-warmed at a cost. The two solve different problems and are often used together.

## Common Mistakes

| Mistake | Why it bites | Fix |
| --- | --- | --- |
| `boto3.client()` inside the handler | 50-200ms wasted per invocation | Hoist to module scope |
| `import pandas` at module top when only one branch uses it | 300-700ms added to every cold start | Lazy-import inside the function that needs it |
| Returning a plain `raise` for one bad SQS message | Entire batch retried, queue stalls | Return `{"batchItemFailures": [...]}` |
| `logger.info(event)` on a request handler | Leaks PII, secrets, tokens to CloudWatch | Log a redacted subset of fields, use Powertools log filters |
| Lambda timeout shorter than downstream service SLA | Function dies with no exception, partial work, no clean DLQ | Set Lambda timeout = downstream timeout + buffer; check `get_remaining_time_in_millis` |
| `print()` instead of structured logger | No correlation id, no level filter, hard to query | Use Powertools `Logger` |
| No reserved concurrency on a critical path Lambda | A noisy neighbor function exhausts the account-wide concurrency pool | Set reserved concurrency on every customer-facing function |
| DLQ configured but no alarm | Failures pile up silently for weeks | CloudWatch alarm on `ApproximateNumberOfMessagesVisible` for the DLQ |
| Heavy module-scope init for code paths most invocations skip | Cold-start tax paid even when the path is never taken | Move to lazy-initialized helper, gate on first use |
| Async Lambda with no on-failure destination | Failed events vanish | Configure EventBridge on-failure destination or DLQ |
| Mutating module-scope state in the handler | Leaks across invocations on warm containers | Treat module scope as read-only after init |

## Quick Reference

| Task | Code or value |
| --- | --- |
| Handler signature | `def handler(event: dict, context: LambdaContext) -> dict` |
| Time remaining | `context.get_remaining_time_in_millis()` |
| Request id | `context.aws_request_id` |
| API Gateway response | `{"statusCode": 200, "headers": {...}, "body": json.dumps(...)}` |
| SQS partial failure | `{"batchItemFailures": [{"itemIdentifier": msg_id}, ...]}` |
| Logger | `from aws_lambda_powertools import Logger` |
| Tracer | `from aws_lambda_powertools import Tracer` |
| Metrics | `from aws_lambda_powertools import Metrics` |
| Event parser | `from aws_lambda_powertools.utilities.parser import event_parser, BaseModel` |
| Idempotency | `from aws_lambda_powertools.utilities.idempotency import idempotent, DynamoDBPersistenceLayer` |
| Cached SSM lookup | `parameters.get_parameter("/path", max_age=300)` |
| Cached secret lookup | `parameters.get_secret("name", max_age=300)` |
| Build for Lambda x86_64 | `pip install --platform manylinux2014_x86_64 --only-binary=:all: --target ./package -r requirements.txt` |
| Build for Lambda arm64 | `pip install --platform manylinux2014_aarch64 --only-binary=:all: --target ./package -r requirements.txt` |
| Container base image | `public.ecr.aws/lambda/python:3.12` |
| Layer zip layout | `python/<deps>` zipped at the root |
| Decorator order (outer to inner) | `idempotent` → `inject_lambda_context` → `capture_lambda_handler` → `log_metrics` → `event_parser` → handler |
| Recommended memory starting point | 1024 MB, then tune with Power Tuning |
| Architecture | `arm64` unless a dependency requires x86_64 |
| Powertools dev mode | `POWERTOOLS_DEV=true` (pretty logs, no tracing) |
