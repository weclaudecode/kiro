<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern:
  - "**/handler.py"
  - "**/lambda_function.py"
  - "**/lambdas/**/*.py"
---

# Lambda Conventions

## Runtime & packaging
- Python 3.12, `arm64` (Graviton) by default — cheaper and faster for our
  typical workloads.
- Package with `uv pip install --target ./build` then zip; or use a
  container image when the deployment package exceeds 50 MB compressed.
- Layers only for shared deps used by 3+ functions; otherwise duplicate.

## Handler shape

```python
from __future__ import annotations

from aws_lambda_powertools import Logger, Metrics, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

logger = Logger()
tracer = Tracer()
metrics = Metrics()

@logger.inject_lambda_context(log_event=False, correlation_id_path="requestContext.requestId")
@tracer.capture_lambda_handler
@metrics.log_metrics(capture_cold_start_metric=True)
def handler(event: dict, context: LambdaContext) -> dict:
    ...
```

- **Powertools is mandatory** — `Logger`, `Tracer`, `Metrics`. Don't roll
  your own logging.
- `log_event=False` by default; explicitly enable per-function only when
  payloads are non-sensitive.
- Correlation ID propagation is required across SQS/EventBridge hops.

## Cold-start hygiene
- Initialize SDK clients (`boto3.client(...)`) at module scope, not inside
  the handler.
- Lazy-import heavy modules (e.g., `pandas`, `numpy`) inside the function
  that uses them, when only some code paths need them.
- Keep the deployment package small — one fat dep (e.g., `pandas`) doubles
  cold-start.

## Idempotency
Use `aws_lambda_powertools.utilities.idempotency` for any handler triggered
by SQS, EventBridge, or API Gateway with retries. Persist via DynamoDB.

## Errors
- For SQS: throw to let the message return to the queue / DLQ. Don't
  swallow.
- For API Gateway: catch at the edge, return a structured error envelope,
  log the full exception with `logger.exception(...)`.
- Use `aws_lambda_powertools.utilities.parser` (Pydantic) to validate the
  event up-front; bad input → 400, not 500.

## Resource sizing
- Right-size memory with `aws-lambda-power-tuning` before merging. CPU
  scales with memory — sometimes more memory is cheaper end-to-end.
- Set `reservedConcurrency` only when you need to *cap* traffic; otherwise
  rely on account-level concurrency.
- Set a `timeout` that's 1.5–2× the p99 observed runtime, not the max.
