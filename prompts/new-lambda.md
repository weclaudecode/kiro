<!-- Install to: ~/.kiro/prompts/  OR  <project>/.kiro/prompts/ -->
<!-- Invoke as: @new-lambda -->

Scaffold a new Python 3.12 AWS Lambda following our conventions.

Ask me first (one question at a time):
1. Function name (kebab-case, e.g. `ingest-orders`).
2. Trigger source (API Gateway / SQS / EventBridge / S3 / scheduled).
3. Whether it needs to run inside a VPC.
4. Whether it needs idempotency (yes for SQS / EventBridge / retried API GW).

Then generate, in this order:

1. **`src/<function_name>/handler.py`** with the standard powertools decorator
   stack (Logger, Tracer, Metrics), a Pydantic event model for the chosen
   trigger source, and a `handler(event, context)` shaped for that source.
2. **`src/<function_name>/__init__.py`** (empty).
3. **`tests/test_handler.py`** with three tests: happy path, malformed event
   (Pydantic validation error → 400 / DLQ), downstream failure (boto stub
   raises). Use `moto` for AWS mocks.
4. **`pyproject.toml`** under `src/<function_name>/` declaring `boto3`,
   `aws-lambda-powertools[parser,tracer]`, `pydantic`, plus dev deps
   (`pytest`, `moto`, `mypy`, `ruff`). Pin via `uv lock` (run after).
5. **`README.md`** for the function: trigger, IAM permissions required,
   env vars, how to run tests, how to package.
6. **(Only if asked)** A `terraform/main.tf` skeleton with
   `aws_lambda_function`, `aws_iam_role`, `aws_iam_role_policy`,
   `aws_cloudwatch_log_group` (with retention).

Don't write the IaC unless I ask. After generating, print the next steps
(install deps, run tests, package).
