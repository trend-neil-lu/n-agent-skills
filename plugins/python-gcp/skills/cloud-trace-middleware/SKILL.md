---
name: cloud-trace-middleware
description: Request middleware for GCP Cloud Trace context propagation and correlation. Triggers on 'cloud trace', 'x-cloud-trace-context', 'gcp trace middleware', 'trace propagation gcp'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Cloud Trace Middleware

Request context middleware for trace propagation, request ID tracking, and correlation across distributed services.

## Overview

```text
Incoming Request
       │
       ▼
┌──────────────────────────────────────┐
│    X-Cloud-Trace-Context header      │
│    (from Cloud Run / Load Balancer)  │
└──────────────────────────────────────┘
       │
       ▼
RequestContextMiddleware.setup()
       │
       ├── Extract trace_id → request_id
       ├── Set ContextVar (async-safe)
       ├── Sync with logging module
       └── Build request context
       │
       ▼
┌──────────────────────────────────────┐
│           Request Handler            │
│   - All logs include request_id      │
│   - Traces are correlated            │
└──────────────────────────────────────┘
       │
       ▼
add_request_id_to_response()
       │
       ▼
Response with X-Request-ID header
```

## Why This Pattern?

| Feature | Benefit |
|---------|---------|
| ContextVar | Thread/async safe request tracking |
| Trace header extraction | Automatic Cloud Trace correlation |
| Request ID propagation | End-to-end request tracing |
| Response header | Client can correlate with server logs |

## Implementation

### middleware.py

```python
"""
HTTP middleware for Cloud Run services.

Provides:
- Request ID tracking and propagation
- Trace header extraction for logging correlation
- Context propagation for async operations

Note: OpenTelemetry trace context is handled by FlaskInstrumentor.
"""

import contextvars
import uuid
from typing import Any

import flask

from logging_module import (
    get_logger,
    set_request_id as set_logging_request_id,
    set_trace_header,
)

logger = get_logger(__name__)

# Context variable for request ID (thread-safe and async-safe)
_request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id", default=None
)


def get_or_generate_request_id(request: flask.Request) -> str:
    """
    Get request ID from headers or generate a new one.

    Cloud Run provides request IDs in X-Cloud-Trace-Context header.
    Falls back to generating UUID if not available.

    Priority:
    1. X-Cloud-Trace-Context (Cloud Run trace header)
    2. X-Request-ID (standard header)
    3. X-Correlation-ID (alternative header)
    4. Generate UUID (fallback)

    Args:
        request: Flask request object

    Returns:
        Request ID string
    """
    # Try Cloud Run trace header first
    trace_header = request.headers.get("X-Cloud-Trace-Context")
    if trace_header:
        # Format: TRACE_ID/SPAN_ID;o=TRACE_TRUE
        # Use trace ID (before /) as request ID
        trace_id = trace_header.split("/")[0]
        if trace_id:
            return trace_id

    # Try standard request ID headers
    header_request_id = (
        request.headers.get("X-Request-ID")
        or request.headers.get("X-Correlation-ID")
        or request.headers.get("Request-ID")
    )

    if header_request_id:
        return header_request_id

    # Generate new UUID as fallback
    return str(uuid.uuid4())


def set_request_id(request_id: str) -> None:
    """Set request ID in context variable."""
    _request_id_var.set(request_id)


def get_request_id() -> str | None:
    """Get request ID from context variable."""
    return _request_id_var.get()


def get_request_id_safe() -> str:
    """Get request ID with fallback to 'unknown'."""
    return _request_id_var.get() or "unknown"


class RequestContextMiddleware:
    """
    Middleware to set up request context.

    Call setup() at the beginning of each request handler.
    """

    @staticmethod
    def setup(request: flask.Request) -> dict[str, Any]:
        """
        Setup request context from Flask request.

        This method:
        1. Extracts trace ID from X-Cloud-Trace-Context header
        2. Sets request ID in ContextVar for async propagation
        3. Syncs with logging module for trace correlation
        4. Returns context dictionary for use in handler

        Args:
            request: Flask request object

        Returns:
            Context dictionary with request metadata
        """
        # Extract or generate request ID
        request_id = get_or_generate_request_id(request)
        set_request_id(request_id)

        # Sync with logging module for trace correlation
        set_logging_request_id(request_id)

        # Store full trace header for span ID extraction
        trace_header = request.headers.get("X-Cloud-Trace-Context")
        if trace_header:
            set_trace_header(trace_header)

        # Build context dictionary
        context = {
            "request_id": request_id,
            "method": request.method,
            "path": request.path,
            "remote_addr": request.remote_addr,
            "user_agent": request.headers.get("User-Agent", "unknown"),
        }

        # Add Cloud Run specific headers
        if trace_header:
            context["trace_context"] = trace_header

        return context

    @staticmethod
    def get_log_context() -> dict[str, str]:
        """
        Get context for structured logging.

        Returns:
            Dictionary with request_id for logging
        """
        request_id = get_request_id()
        if request_id:
            return {"request_id": request_id}
        return {}


def add_request_id_to_response(
    response: tuple[str, int] | tuple[str, int, dict[str, str]],
) -> tuple[str, int, dict[str, str]]:
    """
    Add request ID to response headers.

    Args:
        response: Original response tuple

    Returns:
        Response tuple with X-Request-ID header
    """
    # Extract existing components
    if len(response) == 2:
        body, status_code = response
        existing_headers: dict[str, str] = {}
    else:
        body, status_code, existing_headers = response

    # Add request ID header
    request_id = get_request_id()
    if request_id:
        headers = {**existing_headers, "X-Request-ID": request_id}
        return (body, status_code, headers)

    return (body, status_code, existing_headers)
```

## Usage

### Basic Setup

```python
# main.py
from flask import Flask, Request
from middleware import (
    RequestContextMiddleware,
    get_request_id,
    add_request_id_to_response,
)
from logging_module import get_logger, log_structured

app = Flask(__name__)
logger = get_logger(__name__)


@app.route("/process", methods=["POST"])
def process(request: Request) -> tuple[str, int, dict[str, str]]:
    # Setup request context at the beginning
    context = RequestContextMiddleware.setup(request)

    logger.info("Processing request", extra={
        "json_fields": {"path": context["path"]}
    })

    try:
        # Your business logic here
        result = do_work(request.get_json())

        log_structured(logger, "info", "Request completed",
                       status="success", result_size=len(result))

        return add_request_id_to_response(("OK", 200))

    except Exception as e:
        log_structured(logger, "error", "Request failed",
                       error_type=type(e).__name__,
                       error_message=str(e))

        return add_request_id_to_response((f"Error: {e}", 500))
```

### With functions-framework

```python
# main.py
import functions_framework
from flask import Request
from middleware import RequestContextMiddleware, add_request_id_to_response


@functions_framework.http
def handler(request: Request) -> tuple[str, int, dict[str, str]]:
    # Setup context
    RequestContextMiddleware.setup(request)

    # Process request
    result = process_message(request)

    return add_request_id_to_response((result, 200))
```

### Accessing Request ID

```python
from middleware import get_request_id, get_request_id_safe

def some_async_function():
    """Request ID is available in async context."""
    request_id = get_request_id()
    if request_id:
        logger.info(f"Processing {request_id}")

def some_other_function():
    """Safe version returns 'unknown' if not set."""
    request_id = get_request_id_safe()
    logger.info(f"Request: {request_id}")
```

## Advanced Patterns

### WSGI Middleware

```python
"""WSGI middleware for automatic context setup."""

from werkzeug.wrappers import Request, Response
from middleware import RequestContextMiddleware, add_request_id_to_response


class RequestContextWSGIMiddleware:
    """WSGI middleware for request context."""

    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        # Create Flask-like request from WSGI environ
        request = Request(environ)

        # Setup context
        RequestContextMiddleware.setup(request)

        # Call wrapped app
        return self.app(environ, start_response)


# Usage
from flask import Flask
app = Flask(__name__)
app.wsgi_app = RequestContextWSGIMiddleware(app.wsgi_app)
```

### With Async (ASGI)

```python
"""ASGI middleware for async frameworks."""

import contextvars
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

# ContextVar works across async boundaries
_request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id", default=None
)


class RequestContextASGIMiddleware(BaseHTTPMiddleware):
    """ASGI middleware for request context."""

    async def dispatch(self, request: Request, call_next):
        # Extract or generate request ID
        trace_header = request.headers.get("x-cloud-trace-context", "")
        if trace_header:
            request_id = trace_header.split("/")[0]
        else:
            request_id = request.headers.get("x-request-id") or str(uuid.uuid4())

        # Set in ContextVar (works with async)
        _request_id_var.set(request_id)

        # Call handler
        response = await call_next(request)

        # Add to response
        response.headers["X-Request-ID"] = request_id

        return response


# Usage with FastAPI
from fastapi import FastAPI
app = FastAPI()
app.add_middleware(RequestContextASGIMiddleware)
```

### Propagating to Downstream Services

```python
"""Propagate request context to downstream services."""

import requests
from middleware import get_request_id


def call_downstream_service(url: str, data: dict) -> dict:
    """
    Call downstream service with context propagation.

    Headers propagated:
    - X-Request-ID: For request correlation
    - X-Cloud-Trace-Context: For distributed tracing
    """
    headers = {}

    # Propagate request ID
    request_id = get_request_id()
    if request_id:
        headers["X-Request-ID"] = request_id
        # Also set as trace header for downstream
        headers["X-Cloud-Trace-Context"] = f"{request_id}/1;o=1"

    response = requests.post(url, json=data, headers=headers)
    return response.json()
```

### With OpenTelemetry

```python
"""Integration with OpenTelemetry tracing."""

from opentelemetry import trace
from opentelemetry.propagate import inject
from middleware import get_request_id

tracer = trace.get_tracer(__name__)


def call_downstream_with_tracing(url: str, data: dict) -> dict:
    """Call downstream service with full trace context."""
    with tracer.start_as_current_span("downstream_call") as span:
        headers = {}

        # Inject OpenTelemetry trace context
        inject(headers)

        # Also include request ID for non-OTel services
        request_id = get_request_id()
        if request_id:
            headers["X-Request-ID"] = request_id

        # Add span attributes
        span.set_attribute("http.url", url)
        span.set_attribute("request.id", request_id or "unknown")

        response = requests.post(url, json=data, headers=headers)

        span.set_attribute("http.status_code", response.status_code)

        return response.json()
```

## X-Cloud-Trace-Context Format

Cloud Run automatically injects the `X-Cloud-Trace-Context` header:

```text
X-Cloud-Trace-Context: TRACE_ID/SPAN_ID;o=TRACE_TRUE
```

| Part | Description | Example |
|------|-------------|---------|
| TRACE_ID | 32-char hex trace ID | `105445aa7843bc8bf206b12000100000` |
| SPAN_ID | Span ID within trace | `1` |
| o=TRACE_TRUE | Sampling decision | `o=1` (sampled) |

Example:

```text
X-Cloud-Trace-Context: 105445aa7843bc8bf206b12000100000/1;o=1
```

## Testing

```python
import pytest
from flask import Flask
from middleware import (
    RequestContextMiddleware,
    get_request_id,
    add_request_id_to_response,
)


@pytest.fixture
def app():
    return Flask(__name__)


def test_extract_trace_id(app):
    """Test trace ID extraction from Cloud Run header."""
    with app.test_request_context(
        headers={"X-Cloud-Trace-Context": "abc123/1;o=1"}
    ):
        from flask import request
        RequestContextMiddleware.setup(request)
        assert get_request_id() == "abc123"


def test_fallback_to_request_id_header(app):
    """Test fallback to X-Request-ID header."""
    with app.test_request_context(
        headers={"X-Request-ID": "req-456"}
    ):
        from flask import request
        RequestContextMiddleware.setup(request)
        assert get_request_id() == "req-456"


def test_generate_uuid_fallback(app):
    """Test UUID generation when no headers."""
    with app.test_request_context():
        from flask import request
        RequestContextMiddleware.setup(request)
        request_id = get_request_id()
        # Should be a valid UUID
        assert len(request_id) == 36
        assert request_id.count("-") == 4


def test_add_request_id_to_response(app):
    """Test response header addition."""
    with app.test_request_context(
        headers={"X-Request-ID": "test-id"}
    ):
        from flask import request
        RequestContextMiddleware.setup(request)

        body, status, headers = add_request_id_to_response(("OK", 200))

        assert headers["X-Request-ID"] == "test-id"
        assert body == "OK"
        assert status == 200


def test_context_isolation():
    """Test that context is isolated between requests."""
    from concurrent.futures import ThreadPoolExecutor

    def process_request(request_id: str) -> str:
        # Simulate setting request ID
        from middleware import set_request_id
        set_request_id(request_id)
        # Return what we get back
        return get_request_id()

    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = [
            executor.submit(process_request, f"req-{i}")
            for i in range(10)
        ]
        results = [f.result() for f in futures]

    # Each request should have its own ID
    assert results == [f"req-{i}" for i in range(10)]
```

## Best Practices

### Do's

- Set up context at the very beginning of request handling
- Use ContextVar for async-safe context storage
- Propagate request ID to downstream services
- Add request ID to response headers
- Sync with logging module for trace correlation

### Don'ts

- Don't use global variables for request context
- Don't forget to set up context in background tasks
- Don't trust client-provided request IDs (validate if needed)
- Don't include sensitive data in request IDs

## Dependencies

```toml
# pyproject.toml
dependencies = [
    "flask>=3.0.0",  # Or your web framework
]
```

## References

- [Cloud Trace Context](https://cloud.google.com/trace/docs/setup#trace-context)
- [Python contextvars](https://docs.python.org/3/library/contextvars.html)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
