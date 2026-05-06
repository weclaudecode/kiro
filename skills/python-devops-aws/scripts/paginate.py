"""Pagination helpers for boto3 list/describe operations.

Provides ``paginate_to_list`` (collect all pages) and ``paginate_iter``
(stream pages) for any operation that supports a paginator. List/describe
APIs silently truncate at 1000 items; never call them once and trust
the result.
"""

from __future__ import annotations

import os
import sys
from collections.abc import Iterator
from typing import Any

import boto3


def paginate_to_list(
    client: Any,
    operation_name: str,
    result_key: str,
    **operation_kwargs: Any,
) -> list[Any]:
    """Run a paginated boto3 operation and collect ``result_key`` from every page.

    Args:
        client: A boto3 client (e.g. ``session.client("s3")``).
        operation_name: The operation name as used by ``get_paginator``
            (e.g. ``"list_objects_v2"``, ``"describe_instances"``).
        result_key: Top-level key in each page whose list value should be
            collected (e.g. ``"Contents"``, ``"Reservations"``, ``"Users"``).
        **operation_kwargs: Forwarded to ``paginator.paginate(...)``.

    Returns:
        Concatenated list of ``page[result_key]`` across all pages. Pages
        without the key contribute nothing.
    """
    paginator = client.get_paginator(operation_name)
    items: list[Any] = []
    for page in paginator.paginate(**operation_kwargs):
        items.extend(page.get(result_key, []))
    return items


def paginate_iter(
    client: Any,
    operation_name: str,
    result_key: str,
    **operation_kwargs: Any,
) -> Iterator[Any]:
    """Stream items from a paginated boto3 operation.

    Use this for large result sets where collecting everything into a list
    would exhaust memory.

    Yields:
        Each item from ``page[result_key]`` across all pages, in order.
    """
    paginator = client.get_paginator(operation_name)
    for page in paginator.paginate(**operation_kwargs):
        yield from page.get(result_key, [])


if __name__ == "__main__":
    # Demo: list all objects in the bucket given by S3_DEMO_BUCKET.
    bucket = os.environ.get("S3_DEMO_BUCKET")
    if not bucket:
        print("Set S3_DEMO_BUCKET to run this demo.")
        sys.exit(1)

    region = os.environ.get("AWS_REGION", "us-east-1")
    s3 = boto3.Session(region_name=region).client("s3")

    objects = paginate_to_list(s3, "list_objects_v2", "Contents", Bucket=bucket)
    print(f"Found {len(objects)} objects in {bucket}.")
    for obj in objects[:5]:
        print(f"  - {obj['Key']} ({obj['Size']} bytes)")
