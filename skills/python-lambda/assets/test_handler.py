"""Pytest scaffolding for a Powertools Lambda handler.

Adapt to the project layout: rename `app` to whatever module your handler
lives in, and update `OrderEvent`-shaped fixtures to match the real event.

Run with:
    POWERTOOLS_DEV=true pytest -q

Dependencies (declare in pyproject.toml dev group):
    pytest, moto[dynamodb], pytest-mock
"""

from __future__ import annotations

import os
from dataclasses import dataclass

# Configure Powertools for test mode BEFORE importing anything that uses it.
os.environ.setdefault("POWERTOOLS_DEV", "true")
os.environ.setdefault("POWERTOOLS_SERVICE_NAME", "orders-test")
os.environ.setdefault("POWERTOOLS_METRICS_NAMESPACE", "OrdersTest")
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")

import boto3  # noqa: E402
import pytest  # noqa: E402
from moto import mock_aws  # noqa: E402


# --- Fake LambdaContext factory -------------------------------------------------


@dataclass
class FakeContext:
    aws_request_id: str = "test-req-1"
    function_name: str = "orders"
    function_version: str = "$LATEST"
    invoked_function_arn: str = "arn:aws:lambda:us-east-1:000000000000:function:orders"
    memory_limit_in_mb: int = 512
    log_group_name: str = "/aws/lambda/orders"
    log_stream_name: str = "stream"
    _remaining_ms: int = 30_000

    def get_remaining_time_in_millis(self) -> int:
        return self._remaining_ms


def make_context(remaining_ms: int = 30_000) -> FakeContext:
    return FakeContext(_remaining_ms=remaining_ms)


# --- Fixtures ------------------------------------------------------------------


@pytest.fixture
def sample_order_event() -> dict:
    return {"order_id": "abc-123", "amount_cents": 1_000, "customer_id": "cust-1"}


@pytest.fixture
def aws_setup():
    """Stand up a mock DynamoDB table for the idempotency persistence layer."""
    with mock_aws():
        ddb = boto3.client("dynamodb", region_name="us-east-1")
        ddb.create_table(
            TableName="orders-idempotency",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield ddb


# --- Tests ---------------------------------------------------------------------


def test_handler_returns_charge_id_for_valid_order(
    aws_setup, sample_order_event, mocker
):
    """Golden path: a well-formed event produces a charge id."""
    # Import after env vars and moto context are set up.
    from app import handler

    mocker.patch("app.charge", return_value="ch_abc-123")

    result = handler(sample_order_event, make_context())

    assert result["order_id"] == "abc-123"
    assert result["charge_id"] == "ch_abc-123"


def test_handler_refuses_when_remaining_time_is_short(
    aws_setup, sample_order_event, mocker
):
    """Error path: handler bails out before doing risky work near timeout."""
    from app import handler

    mocker.patch("app.charge", return_value="ch_abc-123")

    with pytest.raises(RuntimeError, match="insufficient time"):
        handler(sample_order_event, make_context(remaining_ms=500))
