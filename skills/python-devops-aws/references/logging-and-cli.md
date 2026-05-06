# Logging and CLI ergonomics

Covers structured JSON logging with structlog and Typer-driven CLIs.

## Logging

Never use `print` in scripts that run unattended. Use structured JSON logging so logs can be queried in CloudWatch Logs Insights, Datadog, or any log aggregator. Always include the AWS request ID from `response["ResponseMetadata"]["RequestId"]` — this is what AWS Support asks for first.

```python
import logging
import sys

import structlog


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=level,
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    )


log = structlog.get_logger()


def delete_object(session: boto3.Session, bucket: str, key: str) -> None:
    s3 = session.client("s3")
    response = s3.delete_object(Bucket=bucket, Key=key)
    log.info(
        "s3.delete_object",
        bucket=bucket,
        key=key,
        request_id=response["ResponseMetadata"]["RequestId"],
        version_id=response.get("VersionId"),
    )
```

When logging errors:

```python
except ClientError as exc:
    log.error(
        "s3.delete_object.failed",
        bucket=bucket,
        key=key,
        error_code=exc.response["Error"]["Code"],
        request_id=exc.response.get("ResponseMetadata", {}).get("RequestId"),
        exc_info=True,
    )
    raise
```

Never log full request/response bodies blindly — they may contain credentials, signed URLs, or PII. Whitelist fields.

## CLI ergonomics

Use Typer for type-hint-driven CLIs. It is built on Click, parses type annotations into argument types, and produces good `--help` output without ceremony. Always provide `--profile`, `--region`, `--dry-run`, and `--yes` for destructive operations. Default to dry-run.

```python
from __future__ import annotations
from typing import Annotated

import boto3
import typer

from mytool.aws.session import make_session
from mytool.logging import configure_logging, log

app = typer.Typer(no_args_is_help=True, add_completion=False)


@app.command()
def delete_old_snapshots(
    older_than_days: Annotated[int, typer.Option(min=1)] = 30,
    profile: Annotated[str | None, typer.Option(help="AWS profile")] = None,
    region: Annotated[str | None, typer.Option(envvar="AWS_REGION")] = None,
    dry_run: Annotated[bool, typer.Option(help="Plan without deleting")] = True,
    yes: Annotated[bool, typer.Option(help="Skip confirmation")] = False,
    log_level: Annotated[str, typer.Option()] = "INFO",
) -> None:
    """Delete EBS snapshots older than N days."""
    configure_logging(log_level)
    session = make_session(profile=profile, region=region)
    snapshots = find_old_snapshots(session, older_than_days)
    log.info("snapshots.found", count=len(snapshots), dry_run=dry_run)

    if dry_run:
        for snap in snapshots:
            log.info("snapshots.would_delete", snapshot_id=snap["SnapshotId"])
        return

    if not yes:
        typer.confirm(f"Delete {len(snapshots)} snapshots?", abort=True)

    for snap in snapshots:
        delete_snapshot(session, snap["SnapshotId"])


if __name__ == "__main__":
    app()
```

Default `dry_run=True` means a user who runs the command without flags gets a plan, not a destructive action. They have to opt in with `--no-dry-run --yes`.

## Packaging and execution

Distribute shared tools as installable packages. Avoid the temptation of "just chmod +x and copy the file" — it bypasses dependency management and breaks the moment someone has a different boto3 version.

Three good execution paths:

1. **Module execution:** `python -m mytool` works once the package is installed. Add `src/mytool/__main__.py` that calls `from mytool.cli import app; app()`.
2. **Entry-point script:** the `[project.scripts]` table in `pyproject.toml` creates a `mytool` console script on install. After `uv pip install .` or `uv tool install .`, users run `mytool ...`.
3. **uv tool / uvx:** `uv tool install .` installs into an isolated venv. `uvx --from . mytool` runs without installing globally.

For internal sharing, publish to a private package index (CodeArtifact, GitHub Packages, internal PyPI) and let users `uv tool install mytool`. For one-off scripts in a repo, `uv run mytool/script.py` is fine — uv resolves deps from `pyproject.toml` automatically.

Shebangs (`#!/usr/bin/env python3`) and `chmod +x` work for personal scripts but fail for shared tools because:

- They depend on whatever Python and packages are on `$PATH`
- They have no way to declare or verify dependency versions
- They break when run from a different working directory
- They cannot be tested in isolation
