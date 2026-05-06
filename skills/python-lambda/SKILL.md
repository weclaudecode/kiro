---
name: python-lambda
description: Use when writing Python AWS Lambda handlers — covers handler structure, cold start optimization, AWS Lambda Powertools, Parameter Store/Secrets Manager, environment variables, error handling and DLQs, packaging with layers or container images, and local testing
---

# Python for AWS Lambda

## Overview

AWS Lambda is a constrained, ephemeral runtime: containers freeze between invocations, can be reaped at any time, have a hard memory ceiling, and bill by the millisecond. The single most important distinction is module-scope (cold-start, paid once) versus handler-scope (per-request, paid every time) — getting that wrong is the difference between a 200ms warm invocation and an 800ms one. AWS Lambda Powertools is treated as non-optional for production handlers; this skill assumes its use throughout.

This skill assumes the boto3 client construction, retry/backoff, pagination, and Python-on-AWS conventions documented in the companion `python-devops-aws` skill. Patterns here are strictly Lambda-specific.

## When to Use

- Writing a new Python Lambda handler from scratch
- Modifying an existing handler (adding an event source, changing the response shape, adding retries)
- Debugging cold start latency, timeouts, or memory pressure
- Wiring an event-driven handler to S3, SQS, SNS, EventBridge, Kinesis, DynamoDB Streams, or API Gateway
- Choosing between zip, layer, or container image packaging
- Adding observability (Powertools Logger, Tracer, Metrics) to a Lambda

When NOT to use: general boto3/Python scripts that run on EC2, ECS, or a developer laptop — see `python-devops-aws` instead. Non-Python runtimes (Node, Go, Java) — the constraints overlap but the import-cost and Powertools details differ.

## The handler model in 5 lines

1. **Module scope** holds reusable state: boto3 clients, HTTP sessions, parsed config, Pydantic models, Powertools singletons. Cold-start cost is paid once and amortized across every warm invocation.
2. **Handler scope** holds per-request state only — never mutate module-scope state from inside the handler.
3. Use Powertools `Logger`, `Tracer`, `Metrics`, `event_parser` (Pydantic), and `idempotency` for structured logging, X-Ray subsegments, EMF metrics, type-safe events, and at-least-once-delivery safety.
4. Match the invocation model (sync / async / stream) to the error-handling strategy — see `references/error-handling.md` for the rules per source.
5. Always check `context.get_remaining_time_in_millis()` before any downstream call that could exceed the remaining budget; the runtime kills the invocation with `SIGKILL` at timeout, with no exception to catch.

For deployment pipelines that build and ship these artifacts, see `gitlab-pipeline` (or your platform equivalent).

## Templates

| File | Use when |
| --- | --- |
| `templates/handler.py` | Starting a new handler — Powertools Logger/Tracer/Metrics, `event_parser` with a Pydantic model, `idempotency` decorator, structured response. |
| `templates/test_handler.py` | Setting up pytest — `make_context()` factory, sample event fixtures, `moto` DynamoDB fixture, golden-path and timeout tests. |
| `templates/Dockerfile` | Packaging as a container image from `public.ecr.aws/lambda/python:3.12`, multi-stage to keep the runtime layer lean. |
| `templates/pyproject.toml` | New project skeleton — Powertools, Pydantic, boto3, dev tooling (pytest, moto, mypy, ruff). |
| `scripts/build_zip.sh` | Building a zip artifact for Linux from any host OS, parameterized by arch and Python version. |

## References

| File | Topic |
| --- | --- |
| `references/handler-structure.md` | Handler signature, `context` object, module vs handler scope, response shapes per event source, sync/async/streaming response types. |
| `references/cold-starts.md` | Lazy imports, module-scope init, SnapStart, provisioned concurrency, memory tuning, ARM. |
| `references/powertools.md` | Logger, Tracer, Metrics (EMF), `event_parser`, `idempotency`, `parameters` for SSM/Secrets Manager. Decorator ordering. |
| `references/error-handling.md` | Sync vs async vs stream invocation, partial batch failures, DLQs, `BatchProcessor`, timeout detection. |
| `references/packaging.md` | Zip, layers, container images, the `--platform manylinux2014_*` flag, AWS-managed Powertools layer. |
| `references/testing.md` | Pytest patterns, fake `LambdaContext`, `moto`, golden event fixtures, RIE smoke tests. |

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
| Build zip x86_64 | `pip install --platform manylinux2014_x86_64 --only-binary=:all: --target ./package -r requirements.txt` |
| Build zip arm64 | `pip install --platform manylinux2014_aarch64 --only-binary=:all: --target ./package -r requirements.txt` |
| Container base image | `public.ecr.aws/lambda/python:3.12` |
| Layer zip layout | `python/<deps>` zipped at the root |
| Decorator order (outer to inner) | `idempotent` → `inject_lambda_context` → `capture_lambda_handler` → `log_metrics` → `event_parser` → handler |
| Recommended memory starting point | 1024 MB, then tune with Power Tuning |
| Architecture | `arm64` unless a dependency requires x86_64 |
| Powertools dev mode | `POWERTOOLS_DEV=true` (pretty logs, no tracing) |
