# Error handling and retries

Lambda's invocation model determines what happens when a handler raises.

## Synchronous (API Gateway, ALB, direct Invoke with `RequestResponse`)

The exception is returned to the caller as an unhandled error. There is no automatic retry. The handler should catch expected errors and return a structured error response; only let truly unexpected exceptions propagate.

```python
import json

def handler(event, context):
    try:
        result = do_work(event)
    except ValidationError as e:
        return {"statusCode": 400, "body": json.dumps({"error": str(e)})}
    return {"statusCode": 200, "body": json.dumps(result)}
```

## Asynchronous (S3, SNS, EventBridge, async Invoke)

Lambda retries failed async invocations twice (3 attempts total) by default with exponential backoff. After exhausting retries, the event is sent to the configured DLQ or on-failure destination, or dropped silently if neither is configured. Configure a DLQ (SQS or SNS) or, preferably, an EventBridge on-failure destination, on every async-invoked Lambda.

## Stream and queue (SQS, Kinesis, DynamoDB Streams)

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

Powertools provides a `BatchProcessor` utility that handles the partial-failure protocol correctly:

```python
from aws_lambda_powertools.utilities.batch import (
    BatchProcessor,
    EventType,
    process_partial_response,
)

processor = BatchProcessor(event_type=EventType.SQS)

def record_handler(record):
    body = json.loads(record["body"])
    process(body)

def handler(event, context):
    return process_partial_response(
        event=event, record_handler=record_handler, processor=processor, context=context
    )
```

## When to raise vs catch-and-return

Raise when the entire invocation is a failure that needs DLQ/retry semantics. Catch and return a structured error when the failure is per-item or per-request and downstream consumers expect a normal response shape.

## Detecting timeout before it kills you

Lambda kills the invocation at the configured timeout. The runtime sends `SIGTERM` then `SIGKILL` — there is no exception to catch. Check `context.get_remaining_time_in_millis()` before starting any operation that could exceed the budget:

```python
def handler(event, context):
    remaining_records = list(event["Records"])
    for record in event["Records"]:
        if context.get_remaining_time_in_millis() < 5000:
            logger.warning("near timeout, returning remaining records as failures")
            return {"batchItemFailures": [
                {"itemIdentifier": r["messageId"]}
                for r in remaining_records
            ]}
        process(record)
        remaining_records.pop(0)
    return {"batchItemFailures": []}
```

## DLQ alarms

A DLQ without an alarm is silent failure waiting to happen. Always pair a DLQ with a CloudWatch alarm on `ApproximateNumberOfMessagesVisible` so the team learns about poison messages within minutes, not weeks.
