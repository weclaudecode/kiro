# Error handling

Every boto3 API call can raise `botocore.exceptions.ClientError`. The error code lives in `e.response["Error"]["Code"]` and is the only stable identifier — error messages change. Never catch bare `Exception`; catch `ClientError` and dispatch on the code.

```python
from botocore.exceptions import ClientError


class ResourceNotFound(Exception):
    pass


class AccessDenied(Exception):
    pass


class Throttled(Exception):
    pass


def get_bucket_tagging(session: boto3.Session, bucket: str) -> dict[str, str]:
    s3 = session.client("s3")
    try:
        response = s3.get_bucket_tagging(Bucket=bucket)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        match code:
            case "NoSuchTagSet" | "NoSuchBucket":
                raise ResourceNotFound(bucket) from exc
            case "AccessDenied" | "AccessDeniedException":
                raise AccessDenied(bucket) from exc
            case "ThrottlingException" | "RequestLimitExceeded":
                raise Throttled(code) from exc
            case _:
                raise
    return {t["Key"]: t["Value"] for t in response["TagSet"]}
```

## Codes worth handling explicitly across most services

- `ThrottlingException`, `Throttling`, `RequestLimitExceeded`, `TooManyRequestsException`
- `ResourceNotFoundException`, `NoSuchEntity`, `NoSuchBucket`, `NoSuchKey`
- `AccessDenied`, `AccessDeniedException`, `UnauthorizedOperation`
- `ValidationException`, `InvalidParameterValue`
- `ConditionalCheckFailedException` (DynamoDB)
- `ResourceInUseException`, `ResourceConflictException`

## Decorator ergonomics

```python
from functools import wraps


def translate_client_errors(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code in {"AccessDenied", "AccessDeniedException"}:
                raise AccessDenied(str(exc)) from exc
            if code in {"ThrottlingException", "Throttling"}:
                raise Throttled(str(exc)) from exc
            raise
    return wrapper
```
