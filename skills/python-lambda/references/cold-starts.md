# Cold start optimization

Cold starts have two phases: the runtime boot and the user-code initialization. User-code init is usually the dominant cost and the only one engineers control.

## Lazy imports for heavy SDKs

Top-level imports run on every cold start, even if the code path that needs them is rare. Move heavy imports inside the function that uses them.

```python
def handler(event, context):
    if event.get("mode") == "report":
        import pandas as pd  # only paid for on report invocations
        return build_report(pd, event)
    return fast_path(event)
```

`import json`, `import os`, `import datetime` cost essentially nothing. `import pandas` is 300-700ms. `import numpy` alone is 100-200ms. `import boto3` is 200-400ms but unavoidable. Profile with `python -X importtime -c "import your_module" 2> imports.txt`.

## Init at module scope

Cold-start work pays off across all warm invocations on the same execution environment. Good candidates for module-scope initialization:

- `boto3.client(...)` and `boto3.resource(...)`
- HTTP session objects with connection pooling
- Configuration fetched from SSM Parameter Store or Secrets Manager
- Compiled regular expressions
- Pydantic models, JSON schemas
- Powertools `Logger`, `Tracer`, `Metrics` instances

## SnapStart

SnapStart for Python Lambda is generally available on Python 3.12 and 3.13 runtimes (announced late 2024). It snapshots the initialized execution environment after `init` and restores from the snapshot on cold start, eliminating most user-code init cost. Tradeoffs:

- Incompatible with provisioned concurrency on the same alias
- Requires versioned function aliases
- Module-level state that bakes in time-sensitive values (request signers, short-lived tokens) needs a runtime hook to refresh on restore

Register before-snapshot and after-restore hooks via `snapshot_restore_py` if needed:

```python
from snapshot_restore_py import register_before_snapshot, register_after_restore

def refresh_clients():
    global S3
    S3 = boto3.client("s3")  # rebuild after restore

register_after_restore(refresh_clients)
```

## Provisioned concurrency tradeoffs

Provisioned concurrency keeps N execution environments warm and pre-initialized. Use it for low-latency synchronous APIs where p99 cold-start latency is unacceptable. Costs continue 24/7 whether traffic arrives or not — autoscale provisioned concurrency on a schedule for predictable diurnal traffic.

## Avoid `boto3.client()` per invocation

Creating a client is not free. It loads service models, parses endpoint config, and builds a session. On a 128MB function this is 50-200ms per call. Always hoist clients to module scope.

## Why import discipline matters

A 600ms import-time cost on a 200ms-of-actual-work function turns p50 cold-start latency from 800ms into 1.4s and inflates the GB-second bill by 4x for cold invocations. Treat top-level imports as a budget, not a free list.

## Performance and cost levers

Lambda allocates CPU proportional to memory: doubling memory roughly doubles CPU. A function that runs in 5s at 512 MB may run in 1s at 2048 MB and cost less in total GB-seconds. Use [AWS Lambda Power Tuning](https://github.com/alexcasalboni/aws-lambda-power-tuning) to find the cost-optimal memory setting for a given workload. Re-tune after significant code changes.

ARM (Graviton) is roughly 20% cheaper per GB-second than x86, and on most Python workloads performs equivalently or slightly better. Build with `--platform manylinux2014_aarch64` and set the function architecture to `arm64`.

Ephemeral storage (`/tmp`) defaults to 512 MB and can be raised to 10 GB. Pay only when actually needed — large temp files for video transcoding, ML model downloads, scratch space for large CSV processing.

Reserved concurrency caps the maximum simultaneous executions of a function and protects downstream systems from being overrun during a Lambda traffic spike. Provisioned concurrency keeps environments pre-warmed at a cost. The two solve different problems and are often used together.
