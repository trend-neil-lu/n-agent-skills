---
name: cloud-logging
description: Structured JSON logging for GCP with automatic Cloud Trace correlation. Triggers on 'cloud logging', 'gcp logging', 'cloud trace logging', 'structured logging gcp'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Cloud Logging for GCP Python

Structured JSON logging for Cloud Run services with automatic Cloud Trace correlation and request context propagation.

## Overview

```text
Cloud Run Request
       │
       ▼
X-Cloud-Trace-Context header
       │
       ▼
RequestContextMiddleware
       │
       ├── Extract trace_id, span_id
       │
       ▼
ContextVar (request_id_var, span_id_var)
       │
       ▼
CloudRunJsonFormatter
       │
       ├── logging.googleapis.com/trace
       ├── logging.googleapis.com/spanId
       └── Structured JSON fields
       │
       ▼
stdout → Cloud Logging (auto-capture)
       │
       ▼
Cloud Trace (correlated logs)
```

## Why stdout JSON (Not Cloud Logging Client)?

| Approach | Startup | Memory | Cost | Complexity |
|----------|---------|--------|------|------------|
| JSON to stdout | ~0ms | ~0MB | Free | Low |
| Cloud Logging client | ~500ms | ~50MB | API calls | Medium |

Cloud Run automatically captures stdout/stderr and sends to Cloud Logging. No client library needed.

## Implementation

### logging.py

```python
"""
Structured Cloud Logging for GCP Cloud Run.

Cloud Run Best Practice:
- Write JSON logs to stdout/stderr
- Cloud Run automatically captures and sends to Cloud Logging
- No google-cloud-logging client needed (faster, simpler, cheaper)
- Structured logging with automatic trace correlation
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
span_id_var: ContextVar[str | None] = ContextVar("span_id", default=None)
trace_header_var: ContextVar[str | None] = ContextVar("trace_header", default=None)

# Module-level variables (set during initialization)
_gcp_project_id: str | None = None
_service_version: str | None = None


def set_gcp_project_id(project_id: str) -> None:
    """Set GCP project ID for trace correlation."""
    global _gcp_project_id
    _gcp_project_id = project_id


def set_service_version(version: str) -> None:
    """Set service version for automatic inclusion in all logs."""
    global _service_version
    _service_version = version


class CloudRunJsonFormatter(logging.Formatter):
    """
    JSON formatter for Cloud Run structured logging.

    Formats log records as JSON for automatic Cloud Logging integration.
    Supports context variables for request tracking across async operations.
    """

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON for Cloud Logging."""
        # Base log object with Cloud Logging fields
        log_obj: dict[str, Any] = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "logger": record.name,
            "logging.googleapis.com/insertId": str(uuid.uuid4()),
        }

        # Add source location (clickable in Cloud Console)
        log_obj["sourceLocation"] = {
            "file": record.pathname,
            "line": record.lineno,
            "function": record.funcName,
        }

        # Add context variables (request tracking)
        request_id = request_id_var.get()
        if request_id:
            log_obj["request_id"] = request_id

        # Add structured fields from extra.json_fields
        if hasattr(record, "json_fields") and isinstance(record.json_fields, dict):
            log_obj.update(record.json_fields)

        # Add trace context for request correlation
        if request_id and _gcp_project_id:
            log_obj["logging.googleapis.com/trace"] = (
                f"projects/{_gcp_project_id}/traces/{request_id}"
            )

        # Add span ID if available
        trace_header = trace_header_var.get()
        if trace_header and "/" in trace_header:
            span_info = trace_header.split("/")[1]
            span_id = span_info.split(";")[0] if ";" in span_info else span_info
            log_obj["logging.googleapis.com/spanId"] = span_id
        elif span_id_var.get():
            log_obj["logging.googleapis.com/spanId"] = span_id_var.get()

        # Add exception info if present
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
            log_obj["stack_trace"] = self.formatException(record.exc_info)

        # Add Cloud Run metadata (auto-injected environment variables)
        service_name = os.getenv("K_SERVICE")
        revision = os.getenv("K_REVISION")
        if service_name:
            log_obj["service"] = service_name
        if revision:
            log_obj["revision"] = revision

        # Add service version
        if _service_version:
            log_obj["version"] = _service_version

        # Add log source identifier
        log_obj["log_source"] = "application"

        return json.dumps(log_obj)


def setup_cloud_logging(log_level: str | None = None) -> None:
    """
    Setup Cloud Run logging (JSON to stdout).

    Args:
        log_level: Log level string (DEBUG, INFO, WARNING, ERROR, CRITICAL).
                   Defaults to LOG_LEVEL env var or INFO.

    Best Practices:
        - In Cloud Run, logs are automatically captured from stdout
        - Use logger.info("msg", extra={"json_fields": {...}}) for structured logs
        - Use set_request_id() to add request context to all logs
        - For local development, uses human-readable format
    """
    # Determine log level
    level_str = log_level or os.getenv("LOG_LEVEL", "INFO")
    level = getattr(logging, level_str.upper() if level_str else "INFO", logging.INFO)

    # Check if running in Cloud Run
    is_cloud_run = os.getenv("K_SERVICE") is not None

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    # Remove existing handlers to avoid duplicates
    root_logger.handlers.clear()

    # Create console handler (stdout)
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)

    if is_cloud_run:
        # Cloud Run: Use JSON formatter
        handler.setFormatter(CloudRunJsonFormatter())

        # Silence noisy loggers (except in DEBUG mode)
        if level > logging.DEBUG:
            for logger_name in [
                "google.auth.transport.requests",
                "urllib3.connectionpool",
                "google.cloud",
                "werkzeug",
                "functions_framework",
            ]:
                logging.getLogger(logger_name).setLevel(logging.WARNING)
    else:
        # Local development: Use human-readable format
        handler.setFormatter(logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        ))

    root_logger.addHandler(handler)


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance.

    Args:
        name: Logger name (typically __name__)

    Returns:
        Configured logger instance
    """
    return logging.getLogger(name)


def log_structured(
    logger: logging.Logger,
    level: str,
    message: str,
    **fields: Any,
) -> None:
    """
    Log a structured message with JSON fields.

    Args:
        logger: Logger instance
        level: Log level (debug, info, warning, error, critical)
        message: Log message
        **fields: Additional fields to include

    Example:
        >>> log_structured(logger, "info", "File processed",
        ...                bucket="my-bucket", file="doc.pdf", duration_ms=150)
    """
    log_func = getattr(logger, level.lower())
    log_func(message, extra={"json_fields": fields})


def set_request_id(request_id: str) -> None:
    """Set request ID in context for all subsequent logs."""
    request_id_var.set(request_id)


def set_span_id(span_id: str) -> None:
    """Set span ID in context for distributed tracing."""
    span_id_var.set(span_id)


def set_trace_header(trace_header: str) -> None:
    """
    Set full trace header for span ID extraction.

    Format: TRACE_ID/SPAN_ID;o=TRACE_TRUE
    """
    trace_header_var.set(trace_header)
```

### Request Context Middleware

```python
"""Request context middleware for trace correlation."""

from flask import Flask, Request, g
from logging_module import set_request_id, set_trace_header


class RequestContextMiddleware:
    """
    WSGI middleware for request context propagation.

    Extracts trace context from X-Cloud-Trace-Context header
    and sets context variables for logging correlation.
    """

    def __init__(self, app: Flask) -> None:
        self.app = app
        self._setup_hooks()

    def _setup_hooks(self) -> None:
        """Setup Flask request hooks."""
        @self.app.before_request
        def before_request() -> None:
            from flask import request
            self._extract_trace_context(request)

    def _extract_trace_context(self, request: Request) -> None:
        """Extract and set trace context from request headers."""
        # X-Cloud-Trace-Context: TRACE_ID/SPAN_ID;o=TRACE_TRUE
        trace_header = request.headers.get("X-Cloud-Trace-Context", "")

        if trace_header:
            set_trace_header(trace_header)
            # Extract trace ID (before the /)
            trace_id = trace_header.split("/")[0] if "/" in trace_header else trace_header
            set_request_id(trace_id)
            g.trace_id = trace_id
        else:
            # Generate request ID if no trace header
            import uuid
            request_id = str(uuid.uuid4())
            set_request_id(request_id)
            g.trace_id = request_id
```

## Usage

### Basic Setup

```python
# main.py
from flask import Flask
from logging_module import (
    setup_cloud_logging,
    set_gcp_project_id,
    set_service_version,
    get_logger,
    log_structured,
)
from middleware import RequestContextMiddleware

# Initialize logging before anything else
setup_cloud_logging()

# Set project ID for trace correlation
set_gcp_project_id("my-project-id")
set_service_version("1.0.0")

app = Flask(__name__)
RequestContextMiddleware(app)

logger = get_logger(__name__)


@app.route("/process")
def process():
    # Simple logging
    logger.info("Processing request")

    # Structured logging
    logger.info("File processed", extra={
        "json_fields": {
            "bucket": "my-bucket",
            "file": "document.pdf",
            "duration_ms": 150,
        }
    })

    # Using convenience function
    log_structured(logger, "info", "Operation complete",
                   status="success", items_processed=10)

    return {"status": "ok"}
```

### Health Endpoints

```python
@app.route("/health")
def health():
    """Health check endpoint (not logged with JSON to reduce noise)."""
    return {"status": "healthy"}, 200


@app.route("/startup")
def startup():
    """Startup probe endpoint."""
    return {"status": "ready"}, 200
```

### Error Logging

```python
@app.route("/risky-operation")
def risky_operation():
    try:
        result = do_something_risky()
        return result
    except Exception as e:
        logger.error(
            "Operation failed",
            exc_info=True,  # Include full traceback
            extra={
                "json_fields": {
                    "error_type": type(e).__name__,
                    "error_message": str(e),
                    "operation": "risky_operation",
                }
            }
        )
        return {"error": "Internal error"}, 500
```

## Cloud Logging Query Examples

### Find all logs for a trace

```sql
-- In Cloud Logging query
trace="projects/my-project/traces/abc123"
```

### Find errors with specific fields

```sql
severity="ERROR"
jsonPayload.bucket="my-bucket"
jsonPayload.error_type="ValueError"
```

### Find slow operations

```sql
jsonPayload.duration_ms > 1000
resource.type="cloud_run_revision"
```

### Group by request

```sql
jsonPayload.request_id="req-123"
```

## Cloud Logging Special Fields

| Field | Description |
|-------|-------------|
| `severity` | Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL) |
| `logging.googleapis.com/trace` | Full trace path for correlation |
| `logging.googleapis.com/spanId` | Span ID for distributed tracing |
| `logging.googleapis.com/insertId` | Unique log entry ID |
| `sourceLocation` | File, line, function (clickable in console) |

## Best Practices

### Do's

- Initialize logging at module load (before Flask app)
- Use `extra={"json_fields": {...}}` for structured data
- Include relevant context (bucket, file, operation, duration)
- Use context variables for request tracking
- Log at appropriate levels (DEBUG for details, INFO for operations)

### Don'ts

- Don't use google-cloud-logging client in Cloud Run
- Don't log sensitive data (credentials, PII)
- Don't log large payloads (file contents)
- Don't create loggers inside request handlers
- Don't ignore trace context from headers

## Integration with OpenTelemetry

If using OpenTelemetry for tracing, the logging module complements it:

```python
from observability import setup_tracing
from logging_module import setup_cloud_logging, set_gcp_project_id

# Setup both
setup_cloud_logging()
setup_tracing(service_name="my-service")
set_gcp_project_id("my-project")

# Logs will be correlated with traces automatically
```

## Dependencies

```toml
# pyproject.toml - No additional dependencies needed!
# Uses only Python standard library
```

## References

- [Cloud Logging Structured Logging](https://cloud.google.com/logging/docs/structured-logging)
- [Cloud Run Logging](https://cloud.google.com/run/docs/logging)
- [Cloud Trace Context](https://cloud.google.com/trace/docs/setup#trace-context)
