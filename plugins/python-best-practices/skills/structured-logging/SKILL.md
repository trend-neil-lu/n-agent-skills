---
name: structured-logging
description: Structured JSON logging for Python applications with context variables and environment awareness. Triggers on 'structured logging', 'json logging', 'logging best practices', 'python logging'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Structured Logging for Python

Production-ready structured JSON logging with context variables, environment awareness, and extensibility.

## Overview

```text
Application Code
       │
       ├── logger.info("message", extra={"json_fields": {...}})
       │
       ▼
StructuredJsonFormatter
       │
       ├── Timestamp (ISO 8601)
       ├── Severity level
       ├── Message
       ├── Source location
       ├── Context variables (request_id, etc.)
       └── Custom fields
       │
       ▼
stdout (JSON) → Log aggregator
```

## Why Structured Logging?

| Feature | Benefit |
|---------|---------|
| JSON format | Machine-parseable, queryable |
| Context variables | Async-safe request tracking |
| Source location | Clickable in log viewers |
| Environment detection | Different format for dev/prod |

## Implementation

### logging_config.py

```python
"""
Structured logging for Python applications.

Features:
- JSON output for production
- Human-readable output for development
- Context variables for request tracking
- Source location for debugging
"""

import json
import logging
import os
import sys
import uuid
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any

# Context variables for request tracking (async-safe)
request_id_var: ContextVar[str | None] = ContextVar("request_id", default=None)
correlation_id_var: ContextVar[str | None] = ContextVar("correlation_id", default=None)


class StructuredJsonFormatter(logging.Formatter):
    """
    JSON formatter for structured logging.

    Outputs logs as JSON for easy parsing by log aggregators.
    """

    def __init__(self, service_name: str | None = None):
        super().__init__()
        self.service_name = service_name or os.getenv("SERVICE_NAME", "app")

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON."""
        log_obj: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "service": self.service_name,
        }

        # Add source location
        log_obj["source"] = {
            "file": record.pathname,
            "line": record.lineno,
            "function": record.funcName,
        }

        # Add context variables
        request_id = request_id_var.get()
        if request_id:
            log_obj["request_id"] = request_id

        correlation_id = correlation_id_var.get()
        if correlation_id:
            log_obj["correlation_id"] = correlation_id

        # Add structured fields from extra.json_fields
        if hasattr(record, "json_fields") and isinstance(record.json_fields, dict):
            log_obj.update(record.json_fields)

        # Add exception info if present
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_obj)


class HumanReadableFormatter(logging.Formatter):
    """Human-readable formatter for development."""

    def __init__(self):
        super().__init__(
            fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )


def setup_logging(
    log_level: str | None = None,
    service_name: str | None = None,
    force_json: bool = False,
) -> None:
    """
    Setup structured logging.

    Args:
        log_level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        service_name: Service name for log identification
        force_json: Force JSON output even in development
    """
    # Determine log level
    level_str = log_level or os.getenv("LOG_LEVEL", "INFO")
    level = getattr(logging, level_str.upper(), logging.INFO)

    # Determine if running in production
    is_production = force_json or os.getenv("ENVIRONMENT") in ("production", "prod")

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    root_logger.handlers.clear()

    # Create handler
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)

    if is_production:
        handler.setFormatter(StructuredJsonFormatter(service_name))
    else:
        handler.setFormatter(HumanReadableFormatter())

    root_logger.addHandler(handler)


def get_logger(name: str) -> logging.Logger:
    """Get a logger instance."""
    return logging.getLogger(name)


def log_structured(
    logger: logging.Logger,
    level: str,
    message: str,
    **fields: Any,
) -> None:
    """
    Log a structured message with additional fields.

    Args:
        logger: Logger instance
        level: Log level (debug, info, warning, error, critical)
        message: Log message
        **fields: Additional structured fields

    Example:
        >>> log_structured(logger, "info", "User logged in",
        ...                user_id="123", ip="10.0.0.1")
    """
    log_func = getattr(logger, level.lower())
    log_func(message, extra={"json_fields": fields})


def set_request_id(request_id: str) -> None:
    """Set request ID for all subsequent logs in this context."""
    request_id_var.set(request_id)


def set_correlation_id(correlation_id: str) -> None:
    """Set correlation ID for distributed tracing."""
    correlation_id_var.set(correlation_id)


def get_request_id() -> str | None:
    """Get current request ID."""
    return request_id_var.get()


def generate_request_id() -> str:
    """Generate a new request ID."""
    return str(uuid.uuid4())
```

## Usage

### Basic Setup

```python
from logging_config import setup_logging, get_logger, log_structured

# Initialize at application startup
setup_logging(log_level="INFO", service_name="my-service")

logger = get_logger(__name__)

# Simple logging
logger.info("Application started")

# Structured logging
logger.info("User action", extra={
    "json_fields": {
        "user_id": "123",
        "action": "login",
        "ip_address": "10.0.0.1",
    }
})

# Using convenience function
log_structured(logger, "info", "Order processed",
               order_id="ORD-456",
               amount=99.99,
               currency="USD")
```

### With Request Context

```python
from logging_config import (
    setup_logging,
    get_logger,
    set_request_id,
    generate_request_id,
)

setup_logging()
logger = get_logger(__name__)


def handle_request(request):
    # Set request ID at the start
    request_id = request.headers.get("X-Request-ID") or generate_request_id()
    set_request_id(request_id)

    # All subsequent logs include request_id automatically
    logger.info("Processing request")
    do_work()
    logger.info("Request completed")
```

### Error Logging

```python
try:
    result = risky_operation()
except Exception as e:
    logger.error(
        "Operation failed",
        exc_info=True,  # Include traceback
        extra={
            "json_fields": {
                "operation": "risky_operation",
                "error_type": type(e).__name__,
            }
        }
    )
```

## Output Examples

### Production (JSON)

```json
{
  "timestamp": "2025-01-06T10:30:00+00:00",
  "severity": "INFO",
  "message": "Order processed",
  "logger": "app.orders",
  "service": "order-service",
  "source": {
    "file": "/app/orders.py",
    "line": 42,
    "function": "process_order"
  },
  "request_id": "abc-123",
  "order_id": "ORD-456",
  "amount": 99.99
}
```

### Development (Human-readable)

```text
2025-01-06 10:30:00 - app.orders - INFO - Order processed
```

## Best Practices

### Do's

- Initialize logging at application startup
- Use `extra={"json_fields": {...}}` for structured data
- Include relevant context (IDs, durations, sizes)
- Use appropriate log levels
- Set request ID early in request handling

### Don'ts

- Don't log sensitive data (passwords, tokens, PII)
- Don't log large payloads (file contents)
- Don't create loggers inside functions
- Don't use print() for logging

## Dependencies

```toml
# pyproject.toml - No additional dependencies!
# Uses only Python standard library
```

## References

- [Python Logging](https://docs.python.org/3/library/logging.html)
- [Structured Logging](https://www.structlog.org/)
- [12 Factor App - Logs](https://12factor.net/logs)
