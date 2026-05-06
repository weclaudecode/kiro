"""Application-level retry with full-jitter exponential backoff.

botocore's built-in retries cover transport errors and a fixed set of
service codes. This module covers the cases botocore does not: eventual
consistency, custom "resource not yet visible" loops, and any third-party
call you want to retry on a domain-specific predicate.
"""

from __future__ import annotations

import functools
import random
import time
from collections.abc import Callable
from typing import TypeVar

T = TypeVar("T")


def retry_with_backoff(
    fn: Callable[[], T],
    *,
    is_retryable: Callable[[Exception], bool],
    max_attempts: int = 6,
    base_delay: float = 0.5,
    max_delay: float = 30.0,
    sleep: Callable[[float], None] = time.sleep,
) -> T:
    """Call ``fn()`` with full-jitter exponential backoff on retryable exceptions.

    Args:
        fn: Zero-arg callable to invoke.
        is_retryable: Predicate that returns ``True`` for exceptions that
            should trigger a retry. Any other exception propagates immediately.
        max_attempts: Total attempts before giving up (initial call counts).
        base_delay: Base delay in seconds for the exponential schedule.
        max_delay: Cap on the per-attempt delay (before jitter).
        sleep: Sleep function, injectable for testing.

    Returns:
        Whatever ``fn()`` returns on success.

    Raises:
        The last retryable exception if ``max_attempts`` is exhausted, or
        any non-retryable exception immediately.
    """
    last_exc: Exception | None = None
    for attempt in range(max_attempts):
        try:
            return fn()
        except Exception as exc:
            if not is_retryable(exc):
                raise
            last_exc = exc
            if attempt == max_attempts - 1:
                break
            delay = min(max_delay, base_delay * (2**attempt))
            sleep(random.uniform(0, delay))
    assert last_exc is not None
    raise last_exc


def retryable(
    *,
    is_retryable: Callable[[Exception], bool],
    max_attempts: int = 6,
    base_delay: float = 0.5,
    max_delay: float = 30.0,
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    """Decorator form of :func:`retry_with_backoff`.

    Example:
        >>> from botocore.exceptions import ClientError
        >>> def is_throttle(e: Exception) -> bool:
        ...     return (
        ...         isinstance(e, ClientError)
        ...         and e.response["Error"]["Code"] in {"Throttling", "ThrottlingException"}
        ...     )
        >>> @retryable(is_retryable=is_throttle)
        ... def describe_thing(client, thing_id):
        ...     return client.describe_thing(ThingId=thing_id)
    """

    def decorator(fn: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(fn)
        def wrapper(*args: object, **kwargs: object) -> T:
            return retry_with_backoff(
                lambda: fn(*args, **kwargs),
                is_retryable=is_retryable,
                max_attempts=max_attempts,
                base_delay=base_delay,
                max_delay=max_delay,
            )

        return wrapper

    return decorator


if __name__ == "__main__":
    # Demo: retry a flaky function until it succeeds.
    state = {"calls": 0}

    def flaky() -> str:
        state["calls"] += 1
        if state["calls"] < 3:
            raise ConnectionError("transient")
        return "ok"

    result = retry_with_backoff(
        flaky,
        is_retryable=lambda e: isinstance(e, ConnectionError),
        base_delay=0.05,
        max_delay=0.5,
    )
    print(f"Result: {result} after {state['calls']} attempts")
