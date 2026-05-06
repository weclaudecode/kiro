---
name: python-devops-aws
description: Use when writing Python scripts, CLI tools, or automation that runs outside Lambda and interacts with AWS via boto3 — covers boto3 client/resource patterns, credentials and assume-role, retries and pagination, error handling, logging, packaging, and testing
---

# Python for DevOps with AWS

## Overview

Production Python for DevOps is explicit, observable, and idempotent. boto3 has sharp edges — implicit sessions, default retries that hide throttling, list APIs that silently truncate at 1000 items, and credential resolution that varies by execution environment. This skill collects the patterns and reusable helpers that keep AWS automation honest in scripts, CLIs, and long-running jobs running on EC2, ECS, developer laptops, and CI runners.

## When to Use

Use this skill when:

- Writing a script that calls AWS APIs from a CI runner, EC2 instance, ECS task, or local laptop
- Building a CLI tool that wraps AWS operations (deployments, IAM audits, cost reports, S3 sync)
- Automating IAM, S3, EC2, RDS, or other AWS resources from a runner
- Writing one-off remediation scripts that need to be safe and re-runnable
- Creating shared platform tooling distributed to multiple engineers
- Building data-pipeline glue that orchestrates AWS services from a long-running process

**When NOT to use:** for AWS Lambda handler code, see the `python-lambda` skill. Lambda has a different cold-start, packaging, and credential model that is covered there.

## The 5 things to get right

- **Explicit `boto3.Session`** — never call module-level `boto3.client(...)`; pass a session into every function
- **Always `get_paginator()`** — never assume a single `list_*` / `describe_*` call returns everything
- **Catch `ClientError`** — parse `e.response["Error"]["Code"]`; never catch bare `Exception`
- **Structured logging with `RequestId`** — include `response["ResponseMetadata"]["RequestId"]` on every log line
- **`botocore.config.Config` for retries** — set `retries={"mode": "standard" | "adaptive", "max_attempts": N}` per client

## Project skeleton

Use PEP 621 metadata, a lockfile (`uv.lock`), and the `src/` layout. Copy `templates/pyproject.toml` as a starting point — it is wired for `boto3`, `boto3-stubs`, `structlog`, `typer`, `pytest`, `moto`, `mypy`, and `ruff`, with a `[project.scripts]` entry point ready to rename.

## Reusable helpers

| Need | File |
|---|---|
| Assume role into another account | `scripts/aws_session.py` |
| Paginate any list operation | `scripts/paginate.py` |
| Retry with exponential backoff | `scripts/retry.py` |
| Structured JSON logging | `scripts/logging_setup.py` |

Each script is self-contained Python 3.11+ with type hints, docstrings, and a `__main__` demo. Drop them into `src/<package>/` and import directly.

## Deeper reference

| File | Covers |
|---|---|
| `references/boto3-patterns.md` | Client vs resource, sessions, credential resolution, assume-role, region, type hints |
| `references/reliability.md` | Retry modes, pagination, idempotency tokens, eventual-consistency backoff, waiters |
| `references/error-handling.md` | `ClientError` patterns, common service codes, typed domain exceptions, decorators |
| `references/logging-and-cli.md` | structlog setup, Typer CLIs, `--dry-run`/`--yes` defaults, packaging and execution |
| `references/testing.md` | Project layout, `moto` fixtures, `Stubber` for error paths, when to use which |

## Common Mistakes

| Mistake | Why it bites | Fix |
|---|---|---|
| Using the default `boto3.client(...)` in a multi-account script | Hidden process-wide state crosses credentials between accounts | Pass `boto3.Session` explicitly into every function |
| Calling `list_objects_v2` / `describe_*` once and trusting the result | Silently truncates at 1000 items in production | Use `client.get_paginator(...).paginate(...)` always |
| Catching `Exception` around a boto3 call | Swallows code bugs and AWS errors alike, hides the error code | Catch `ClientError` and match on `e.response["Error"]["Code"]` |
| Hard-coding `region_name="us-east-1"` | Script runs in the wrong region in another account or CI environment | Require `--region` or `AWS_REGION` env var, fail loud if missing |
| `time.sleep(30)` while waiting for a resource | Brittle, slow, fails under load | Use built-in waiters; for custom waits, exponential backoff with jitter |
| Logging `event` or full API response | Leaks credentials, signed URLs, PII into logs | Whitelist fields; always log `RequestId`, never raw responses |
| `def helper(items: list = []):` | Mutable default shared across calls causes phantom data | Use `items: list \| None = None` and assign inside the function |
| `boto3.resource("s3")` for new code | Resource interface is being deprecated in boto3 v2 | Use `client` and write thin wrappers if OO ergonomics matter |
| Running scripts as `chmod +x foo.py` from random checkouts | No dep pinning, no reproducibility, version drift | Package as a project, install with `uv tool install .`, run via entry point |
| `print()` for status output in unattended jobs | Cannot filter by level, no structure, breaks when piped | structlog + JSON renderer; `print` only for interactive CLI output |

## Quick Reference

| Need | One-liner |
|---|---|
| Explicit session | `session = boto3.Session(profile_name=..., region_name=...)` |
| Tuned retries | `Config(retries={"mode": "adaptive", "max_attempts": 10})` |
| Paginate | `client.get_paginator(op).paginate(**params)` |
| Wait for state | `client.get_waiter(name).wait(...)` |
| Parse error code | `exc.response["Error"]["Code"]` on `ClientError` |
| Mock AWS in tests | `with mock_aws(): ...` from `moto` |
| Stub specific call | `Stubber(client).add_response(...)` / `add_client_error(...)` |
| Typed clients | `boto3-stubs[s3,ec2,sts,iam]` + `TYPE_CHECKING` import |
