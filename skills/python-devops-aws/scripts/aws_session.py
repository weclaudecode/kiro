"""Cross-account AWS session helper.

Provides ``get_session_for_account`` to assume a role into a target account
and return a ready-to-use ``boto3.Session``. Suitable for scripts that run
for less than the role's max session duration (default 1 hour). For
long-running processes, wrap with ``RefreshableCredentials`` or re-assume
periodically.
"""

from __future__ import annotations

import os
import sys

import boto3
from botocore.config import Config

_DEFAULT_CONFIG = Config(retries={"mode": "standard", "max_attempts": 5})


def _caller_session_name(base_session: boto3.Session) -> str:
    """Build a role session name from caller identity, truncated to STS's 64-char limit."""
    sts = base_session.client("sts", config=_DEFAULT_CONFIG)
    identity = sts.get_caller_identity()
    arn = identity["Arn"]
    # arn:aws:iam::123456789012:user/alice -> alice
    # arn:aws:sts::123456789012:assumed-role/Foo/alice -> alice
    principal = arn.rsplit("/", 1)[-1]
    name = f"py-{principal}"
    return name[:64]


def get_session_for_account(
    account_id: str,
    role_name: str,
    region: str,
    base_session: boto3.Session | None = None,
    *,
    session_name: str | None = None,
    duration_seconds: int = 3600,
    external_id: str | None = None,
) -> boto3.Session:
    """Return a ``boto3.Session`` with credentials assumed into ``account_id``.

    Args:
        account_id: 12-digit AWS account ID to assume into.
        role_name: Name of the role in the target account (not the full ARN).
        region: AWS region for the returned session.
        base_session: Session used to call ``sts:AssumeRole``. Defaults to a
            fresh ``boto3.Session()`` resolving credentials from the environment.
        session_name: Override the auto-generated ``RoleSessionName``.
        duration_seconds: Lifetime of the assumed credentials (max governed by
            the role's ``MaxSessionDuration``).
        external_id: Optional ``ExternalId`` for cross-account trust policies.

    Returns:
        A new ``boto3.Session`` configured with the temporary credentials.

    Raises:
        botocore.exceptions.ClientError: If the assume-role call fails.
    """
    base_session = base_session or boto3.Session()
    sts = base_session.client("sts", config=_DEFAULT_CONFIG)
    role_arn = f"arn:aws:iam::{account_id}:role/{role_name}"
    name = session_name or _caller_session_name(base_session)

    kwargs: dict[str, object] = {
        "RoleArn": role_arn,
        "RoleSessionName": name,
        "DurationSeconds": duration_seconds,
    }
    if external_id is not None:
        kwargs["ExternalId"] = external_id

    response = sts.assume_role(**kwargs)
    creds = response["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        region_name=region,
    )


if __name__ == "__main__":
    # Demo: assume into TARGET_ACCOUNT_ID/TARGET_ROLE and list S3 buckets.
    account = os.environ.get("TARGET_ACCOUNT_ID")
    role = os.environ.get("TARGET_ROLE", "OrganizationAccountAccessRole")
    region = os.environ.get("AWS_REGION", "us-east-1")
    if not account:
        print("Set TARGET_ACCOUNT_ID (and optionally TARGET_ROLE) to run this demo.")
        sys.exit(1)

    session = get_session_for_account(account_id=account, role_name=role, region=region)
    print(f"Assumed role into account {account}, region {region}.")
    buckets = session.client("s3").list_buckets()["Buckets"]
    for b in buckets:
        print(f"  - {b['Name']}")
