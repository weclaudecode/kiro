# Local testing

The primary local-testing strategy is `pytest` against the imported handler. Lambda's invocation model is simple enough that a function call with a fake `event` and `context` covers the vast majority of behavior.

## Minimal test scaffold

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

A more complete `test_handler.py` template — with a `make_context()` factory, sample event fixtures, a `moto` fixture, and both golden-path and error-path tests — is provided in `assets/test_handler.py`.

## Mocking AWS calls with `moto`

Use `moto` to fake AWS service calls. The boto3 mocking patterns themselves are covered in the `python-devops-aws` skill; the Lambda-specific addition is hoisting the boto3 client to module scope, which means the test must either (a) patch the module-level client, or (b) configure `moto` before the handler module is imported.

```python
import os
os.environ["AWS_DEFAULT_REGION"] = "us-east-1"

import boto3
import pytest
from moto import mock_aws


@pytest.fixture
def s3_setup():
    with mock_aws():
        s3 = boto3.client("s3")
        s3.create_bucket(Bucket="test-bucket")
        yield s3
```

When importing the handler module triggers boto3 client construction at module scope, ensure `mock_aws()` is active before the import. Often the cleanest approach is to import inside the test function or fixture, after the mock is set up.

## Powertools in tests

The Powertools library has built-in test helpers. Set `POWERTOOLS_DEV=true` to make the logger emit human-readable output during tests. For idempotency, mock the persistence layer or use a `mock_aws()` DynamoDB table.

```python
import os
os.environ["POWERTOOLS_DEV"] = "true"
os.environ["POWERTOOLS_METRICS_NAMESPACE"] = "test"
os.environ["POWERTOOLS_SERVICE_NAME"] = "test"
```

## Property-based and golden-event tests

For event-driven Lambdas, store representative event payloads as JSON fixtures alongside the tests:

```
tests/
  events/
    sqs_single_record.json
    sqs_partial_failure.json
    api_gateway_get.json
  test_handler.py
```

Then load them in the test:

```python
from pathlib import Path
import json

EVENTS = Path(__file__).parent / "events"

def test_sqs_single_record():
    event = json.loads((EVENTS / "sqs_single_record.json").read_text())
    result = handler(event, FakeContext())
    assert result == {"batchItemFailures": []}
```

For schema-level validation, `hypothesis` with Pydantic strategies works well for fuzzing event parsers.

## SAM local invoke and Runtime Interface Emulator

`sam local invoke` runs the handler in a Docker container that mirrors the Lambda runtime. Useful for end-to-end smoke tests against a real binary, but slower than pytest and not a substitute for unit tests. The `aws-lambda-runtime-interface-emulator` is the underlying piece — it runs inside the container image and lets `curl` simulate an invocation:

```
docker run -p 9000:8080 my-lambda-image:latest

curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
    -d '{"order_id":"abc"}'
```

This is the recommended smoke test for container Lambdas before pushing to ECR.
