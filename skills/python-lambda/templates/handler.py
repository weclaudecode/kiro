"""Production-quality Lambda handler template.

How to adapt:
  1. Rename `OrderEvent` and its fields to match the actual event payload.
  2. Replace `charge()` with the real per-request work.
  3. Update `service` and `namespace` strings on Logger / Tracer / Metrics.
  4. Update `event_key_jmespath` on `IdempotencyConfig` to a field that
     uniquely identifies a logical request (idempotency key, request id,
     business primary key — NOT the wire-level message id).
  5. Provision a DynamoDB table named in `DynamoDBPersistenceLayer` with
     partition key `id` (string) and TTL on attribute `expiration`.
  6. Set environment variables on the function:
       POWERTOOLS_SERVICE_NAME=orders
       POWERTOOLS_METRICS_NAMESPACE=Orders
       LOG_LEVEL=INFO
  7. Enable active tracing on the function for X-Ray to receive subsegments.

Decorator order (outer to inner) is significant:
  idempotent → inject_lambda_context → capture_lambda_handler →
  log_metrics → event_parser → handler
"""

from __future__ import annotations

import boto3
from aws_lambda_powertools import Logger, Metrics, Tracer
from aws_lambda_powertools.metrics import MetricUnit
from aws_lambda_powertools.utilities.idempotency import (
    DynamoDBPersistenceLayer,
    IdempotencyConfig,
    idempotent,
)
from aws_lambda_powertools.utilities.parser import BaseModel, event_parser
from aws_lambda_powertools.utilities.typing import LambdaContext

# --- Module scope: paid once per cold start, reused across warm invocations ---

logger = Logger(service="orders")
tracer = Tracer(service="orders")
metrics = Metrics(namespace="Orders", service="orders")

# boto3 clients hoisted to module scope so they are not rebuilt per invocation.
DDB = boto3.client("dynamodb")

# Idempotency persistence: DynamoDB table with partition key `id` (string)
# and TTL attribute `expiration`.
_persistence = DynamoDBPersistenceLayer(table_name="orders-idempotency")
_idem_config = IdempotencyConfig(
    event_key_jmespath="order_id",
    expires_after_seconds=3600,
    raise_on_no_idempotency_key=True,
)


# --- Event model: validated by Powertools event_parser ---


class OrderEvent(BaseModel):
    order_id: str
    amount_cents: int
    customer_id: str


# --- Per-request work ---


@tracer.capture_method
def charge(order: OrderEvent) -> str:
    """Charge the customer's card. Returns the charge id."""
    logger.info("charging", extra={"order_id": order.order_id})
    # Replace with real implementation.
    return f"ch_{order.order_id}"


# --- Handler ---


@idempotent(persistence_store=_persistence, config=_idem_config)
@logger.inject_lambda_context(correlation_id_path="order_id")
@tracer.capture_lambda_handler
@metrics.log_metrics(capture_cold_start_metric=True)
@event_parser(model=OrderEvent)
def handler(event: OrderEvent, context: LambdaContext) -> dict:
    # Defensive remaining-time check for downstream calls with their own SLA.
    if context.get_remaining_time_in_millis() < 2_000:
        logger.warning("near timeout, refusing to start work")
        raise RuntimeError("insufficient time to charge safely")

    charge_id = charge(event)
    metrics.add_metric(name="OrderCharged", unit=MetricUnit.Count, value=1)

    return {"order_id": event.order_id, "charge_id": charge_id}
