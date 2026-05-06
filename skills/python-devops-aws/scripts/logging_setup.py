"""Structured JSON logging bootstrap with structlog.

Calls to ``configure_logging`` set up a JSON renderer with ISO-8601 UTC
timestamps and log-level fields, suitable for CloudWatch Logs Insights,
Datadog, and other aggregators. Use ``log = structlog.get_logger()`` in
modules and pass kwargs as structured fields.
"""

from __future__ import annotations

import logging
import sys

import structlog


_LEVELS = {
    "DEBUG": logging.DEBUG,
    "INFO": logging.INFO,
    "WARNING": logging.WARNING,
    "ERROR": logging.ERROR,
    "CRITICAL": logging.CRITICAL,
}


def configure_logging(level: str = "INFO") -> None:
    """Configure the root logger and structlog for JSON output to stdout.

    Args:
        level: One of DEBUG, INFO, WARNING, ERROR, CRITICAL (case-insensitive).

    Effects:
        - Routes stdlib ``logging`` records through the same JSON formatter.
        - Adds ISO-8601 UTC timestamps and log-level fields.
        - Renders ``contextvars`` bound via ``structlog.contextvars.bind_contextvars``.
        - Formats exceptions inline via ``format_exc_info``.
    """
    numeric_level = _LEVELS.get(level.upper(), logging.INFO)

    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=numeric_level,
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
        wrapper_class=structlog.make_filtering_bound_logger(numeric_level),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    """Return a structlog logger. ``name`` is included as a bound field if provided."""
    log = structlog.get_logger()
    if name is not None:
        log = log.bind(logger=name)
    return log


if __name__ == "__main__":
    # Demo: emit a few structured records.
    configure_logging("INFO")
    log = get_logger("demo")

    log.info("startup", component="cli", version="0.1.0")
    log.warning("rate_limit_close", remaining=12, limit=100)

    try:
        raise ValueError("synthetic failure")
    except ValueError:
        log.error("operation.failed", op="describe_things", exc_info=True)
