<!-- Install to: ~/.kiro/steering/  OR  <project>/.kiro/steering/ -->
---
inclusion: fileMatch
fileMatchPattern: "**/*.py"
---

# Python Conventions

## Tooling
- Python 3.12. Manage envs and deps with `uv` (`uv venv`, `uv pip install`,
  `uv lock`). Pin via `pyproject.toml` + `uv.lock`.
- `ruff` for lint + format (replaces black, isort, flake8, pyupgrade).
- `mypy --strict` on all new code. Existing untyped modules can be opted-in
  via per-module overrides as they're touched.
- `pytest` only. No `unittest.TestCase` in new code.

## Style
- Type hints on every public function. Prefer `from __future__ import
  annotations` so hints don't import at runtime.
- f-strings only. No `%` or `.format()`.
- Use `pathlib.Path`, not `os.path`.
- Use `match` for closed sets of variants when it improves readability.
- Dataclasses or `pydantic.BaseModel` (v2) for structured data — never
  bare dicts as DTOs across module boundaries.

## Errors
- Never `except:` or `except Exception:` without re-raising or logging.
- Define narrow custom exceptions in the module that owns the error.
- Don't catch what you can't recover from. Let it bubble.

## Imports
- Standard library, then third-party, then first-party — `ruff`/`isort`
  enforces this; don't fight it.
- No wildcard imports (`from x import *`) except in `__init__.py` re-exports
  with `__all__` declared.

## Tests
- `tests/` mirrors the source tree. One test module per source module.
- Each test asserts one behavior; use `pytest.mark.parametrize` for variants.
- Mock at the boundary (`boto3`, HTTP clients), not internals.
- Integration tests against `moto` or `localstack` where possible — never
  against a shared real AWS account.
