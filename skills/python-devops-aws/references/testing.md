# Testing

Use `moto` for unit tests of code that calls AWS. moto patches boto3 to talk to an in-memory mock of the service. Use `botocore.stub.Stubber` for tighter control or services moto does not cover well.

## Project layout

A reproducible Python project uses PEP 621 metadata in `pyproject.toml`, a lockfile (uv, pip-tools, or Poetry), and the src layout. `requirements.txt` alone is not enough: it pins direct deps but not transitive ones, and it does not capture build-time metadata or entry points. A lockfile guarantees the same dep tree on every machine and CI run.

The src layout (`src/mytool/`) prevents accidental imports from the working directory and forces tests to import from the installed package, catching missing-package-data bugs early.

```
mytool/
  pyproject.toml
  uv.lock
  src/mytool/
    __init__.py
    __main__.py
    cli.py
    aws/
      __init__.py
      session.py
      s3.py
  tests/
    test_session.py
    test_s3.py
```

Use `uv sync` to install from the lockfile, `uv lock --upgrade` to refresh it. Commit `uv.lock` (or `requirements.lock`) to the repo.

## moto with pytest fixtures

```python
# tests/test_s3.py
import boto3
import pytest
from moto import mock_aws

from mytool.aws.s3 import list_all_objects


@pytest.fixture
def aws_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    """Set fake credentials so boto3 doesn't hit a real account in tests."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


@pytest.fixture
def session(aws_credentials: None):
    with mock_aws():
        yield boto3.Session(region_name="us-east-1")


def test_list_all_objects_returns_all_pages(session: boto3.Session) -> None:
    s3 = session.client("s3")
    s3.create_bucket(Bucket="test-bucket")
    for i in range(2500):
        s3.put_object(Bucket="test-bucket", Key=f"prefix/obj-{i:05d}", Body=b"x")

    result = list_all_objects(session, "test-bucket", prefix="prefix/")

    assert len(result) == 2500
    assert all(obj["Key"].startswith("prefix/") for obj in result)
```

## Stubber for precise responses

When testing error paths or services with complex responses, use Stubber:

```python
from botocore.stub import Stubber


def test_get_bucket_tagging_handles_no_tag_set() -> None:
    session = boto3.Session(region_name="us-east-1")
    client = session.client("s3")
    with Stubber(client) as stub:
        stub.add_client_error(
            "get_bucket_tagging",
            service_error_code="NoSuchTagSet",
            expected_params={"Bucket": "b"},
        )
        # Inject the stubbed client into your code under test
        with pytest.raises(ResourceNotFound):
            get_bucket_tagging_with_client(client, "b")
```

Use moto for behavior tests (multiple calls, pagination, eventual consistency). Use Stubber for error-path tests where exact control matters.
