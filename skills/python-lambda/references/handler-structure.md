# Handler structure

The canonical Lambda entry point is a single function that takes two positional arguments:

```python
def handler(event: dict, context: "LambdaContext") -> dict:
    ...
```

The runtime imports the module once per execution environment and calls `handler` once per invocation. Anything at module scope runs during the cold start; anything inside the function runs on every invocation.

## What is in `context`

The `context` object exposes runtime metadata. The fields used most often:

- `context.aws_request_id` — unique per invocation, the right value to put in every log line and downstream call
- `context.function_name`, `context.function_version`, `context.invoked_function_arn`
- `context.memory_limit_in_mb` — configured memory, useful for self-tuning batch sizes
- `context.get_remaining_time_in_millis()` — milliseconds left before the runtime kills the invocation; check it before starting any operation that might exceed the budget
- `context.log_group_name`, `context.log_stream_name` — for cross-referencing in CloudWatch

## Module-level vs handler-level state

Initialize anything reusable at module scope. Do per-request work inside the handler.

Wrong:

```python
import boto3

def handler(event, context):
    s3 = boto3.client("s3")  # rebuilt on every invocation; 50-200ms wasted
    obj = s3.get_object(Bucket=event["bucket"], Key=event["key"])
    return {"size": obj["ContentLength"]}
```

Right:

```python
import boto3

S3 = boto3.client("s3")  # constructed once per execution environment

def handler(event, context):
    obj = S3.get_object(Bucket=event["bucket"], Key=event["key"])
    return {"size": obj["ContentLength"]}
```

The same rule applies to database connection pools, HTTP sessions (`requests.Session`, `httpx.Client`), parsed config, ML model artifacts, and Powertools singletons.

## Why `if __name__ == "__main__"` is irrelevant

Lambda imports the handler module by name (`app.handler` from the function configuration). The module is never run as `__main__`. A `__main__` guard is harmless but does nothing useful in deployed code. Keep `__main__` blocks only for local-test scaffolding that should not run in Lambda.

## Returning a response

The shape of the return value depends on the event source. Mismatched return shapes are a common source of silent failures.

### API Gateway (REST or HTTP API, proxy integration)

```python
import json

def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"ok": True}),
        "isBase64Encoded": False,
    }
```

### SQS partial batch failure

The only correct way to handle a poison message in a batch:

```python
def handler(event, context):
    failures = []
    for record in event["Records"]:
        try:
            process(record)
        except Exception:
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
```

### Direct invocation

(`Invoke` API, Step Functions, another Lambda) — return any JSON-serializable value. Step Functions in particular reads the raw return value as the next state's input.

## Sync vs async vs streaming response types

Lambda supports three response delivery modes:

- **Buffered (default sync)**: the runtime waits for `handler` to return, then sends the full response body. Used by API Gateway proxy integration, ALB, and direct `RequestResponse` invocations.
- **Async (event)**: invoker (S3, SNS, EventBridge, async Invoke) does not wait for a response. Return value is discarded. Failures go to retry/DLQ pipeline.
- **Response streaming**: declared via the `awslambdaric` streaming response support and a `RESPONSE_STREAM` invoke mode on Function URLs or Lambda Web Adapter. Handler is an async generator that yields chunks. Useful for LLM token streaming, large file downloads, and time-to-first-byte-sensitive workloads.

Streaming handler shape (Python, via Lambda Web Adapter or runtime API):

```python
async def handler(event, context):
    yield b'{"status":"started"}\n'
    async for chunk in upstream_stream(event):
        yield chunk
    yield b'{"status":"done"}\n'
```

Streaming responses bypass the 6 MB sync response payload cap (up to 20 MB streamed) and start delivering bytes before the handler finishes.
