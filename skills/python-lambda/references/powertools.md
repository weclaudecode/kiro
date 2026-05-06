# AWS Lambda Powertools for Python

Powertools (v3) is the canonical way to do logging, tracing, metrics, parsing, and idempotency on Python Lambda. It is maintained by AWS, integrates with X-Ray, CloudWatch EMF, and standard event sources, and replaces a pile of bespoke utilities.

Install with the extras the function actually needs:

```
aws-lambda-powertools[tracer,parser,validation]
```

For Parameter Store / Secrets Manager helpers, add `parameters`:

```
aws-lambda-powertools[parser,tracer,parameters]
```

## Logger with `inject_lambda_context`

```python
from aws_lambda_powertools import Logger

logger = Logger(service="orders")

@logger.inject_lambda_context(correlation_id_path="requestContext.requestId")
def handler(event, context):
    logger.info("processing order", extra={"order_id": event["orderId"]})
    return {"ok": True}
```

`inject_lambda_context` adds `function_name`, `function_arn`, `function_request_id`, `cold_start`, and the correlation id to every log line as structured JSON.

## Tracer with `@tracer.capture_method`

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

## Metrics with EMF

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

## `event_parser` with Pydantic

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

## `idempotency` decorator

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

## Configuration and secrets via Powertools `parameters`

Powertools provides cached helpers that handle TTL and avoid hammering SSM on every invocation.

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

Environment variables are visible in plain text in the Lambda console to anyone with `lambda:GetFunctionConfiguration`. Use them for non-sensitive config only. Never embed secrets in environment variables. Never log the contents of `event` if it might carry credentials, PII, or payment data.

## Full example combining all of the above

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
