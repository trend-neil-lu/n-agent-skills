---
name: request-context
description: Request context middleware using ContextVar for async-safe request tracking. Triggers on 'request context', 'contextvar', 'request tracking', 'correlation id', 'middleware pattern'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Request Context Middleware

Async-safe request context tracking using Python's ContextVar for request ID propagation across function calls.

## Overview

```text
Incoming Request
       │
       ├── X-Request-ID header (or generate UUID)
       │
       ▼
RequestContext.init()
       │
       ├── Store in ContextVar (async-safe)
       │
       ▼
┌──────────────────────────────────────┐
│         Application Code             │
│                                      │
│   get_request_id() ──► Returns ID    │
│   (works in any function/thread)     │
└──────────────────────────────────────┘
       │
       ▼
Response with X-Request-ID header
```

## Why ContextVar?

| Feature | Thread-local | ContextVar |
|---------|-------------|------------|
| Thread-safe | Yes | Yes |
| Async-safe | No | Yes |
| Copy on async task | No | Yes |
| Python 3.7+ | N/A | Built-in |

## Implementation

### request_context.py

```python
"""
Async-safe request context using ContextVar.

Features:
- Unique request ID tracking
- Works with sync and async code
- Automatic propagation to child contexts
- Header extraction and response injection
"""

import contextvars
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any


# Context variables (async-safe)
_request_id: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id", default=None
)
_correlation_id: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "correlation_id", default=None
)
_request_start_time: contextvars.ContextVar[float | None] = contextvars.ContextVar(
    "request_start_time", default=None
)
_request_metadata: contextvars.ContextVar[dict[str, Any]] = contextvars.ContextVar(
    "request_metadata", default={}
)


def generate_request_id() -> str:
    """Generate a unique request ID."""
    return str(uuid.uuid4())


def set_request_id(request_id: str) -> None:
    """Set request ID for current context."""
    _request_id.set(request_id)


def get_request_id() -> str | None:
    """Get request ID from current context."""
    return _request_id.get()


def get_request_id_safe() -> str:
    """Get request ID with fallback to 'unknown'."""
    return _request_id.get() or "unknown"


def set_correlation_id(correlation_id: str) -> None:
    """Set correlation ID for distributed tracing."""
    _correlation_id.set(correlation_id)


def get_correlation_id() -> str | None:
    """Get correlation ID from current context."""
    return _correlation_id.get()


def set_request_metadata(key: str, value: Any) -> None:
    """Set additional request metadata."""
    metadata = _request_metadata.get().copy()
    metadata[key] = value
    _request_metadata.set(metadata)


def get_request_metadata() -> dict[str, Any]:
    """Get all request metadata."""
    return _request_metadata.get().copy()


@dataclass
class RequestContext:
    """
    Request context container.

    Use with 'with' statement for automatic cleanup.
    """
    request_id: str
    correlation_id: str | None = None
    method: str | None = None
    path: str | None = None
    start_time: float | None = None

    @classmethod
    def init(
        cls,
        request_id: str | None = None,
        correlation_id: str | None = None,
        method: str | None = None,
        path: str | None = None,
    ) -> "RequestContext":
        """
        Initialize request context.

        Args:
            request_id: Request ID (generated if not provided)
            correlation_id: Correlation ID for distributed tracing
            method: HTTP method
            path: Request path

        Returns:
            RequestContext instance
        """
        import time

        req_id = request_id or generate_request_id()
        start_time = time.time()

        # Set context variables
        _request_id.set(req_id)
        _request_start_time.set(start_time)

        if correlation_id:
            _correlation_id.set(correlation_id)

        # Store metadata
        metadata = {
            "method": method,
            "path": path,
            "start_time": datetime.now(UTC).isoformat(),
        }
        _request_metadata.set(metadata)

        return cls(
            request_id=req_id,
            correlation_id=correlation_id,
            method=method,
            path=path,
            start_time=start_time,
        )

    @classmethod
    def from_headers(cls, headers: dict[str, str], **kwargs) -> "RequestContext":
        """
        Initialize context from HTTP headers.

        Extracts:
        - X-Request-ID or X-Correlation-ID for request ID
        - X-Correlation-ID for correlation ID

        Args:
            headers: HTTP headers dict
            **kwargs: Additional context args

        Returns:
            RequestContext instance
        """
        request_id = (
            headers.get("X-Request-ID")
            or headers.get("X-Correlation-ID")
            or headers.get("Request-ID")
        )
        correlation_id = headers.get("X-Correlation-ID")

        return cls.init(
            request_id=request_id,
            correlation_id=correlation_id,
            **kwargs,
        )

    def elapsed_ms(self) -> int | None:
        """Get elapsed time in milliseconds."""
        if self.start_time is None:
            return None
        import time
        return int((time.time() - self.start_time) * 1000)

    def to_headers(self) -> dict[str, str]:
        """Get headers to add to response."""
        headers = {"X-Request-ID": self.request_id}
        if self.correlation_id:
            headers["X-Correlation-ID"] = self.correlation_id
        return headers

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for logging."""
        return {
            "request_id": self.request_id,
            "correlation_id": self.correlation_id,
            "method": self.method,
            "path": self.path,
            "elapsed_ms": self.elapsed_ms(),
        }


def clear_context() -> None:
    """Clear all context variables."""
    _request_id.set(None)
    _correlation_id.set(None)
    _request_start_time.set(None)
    _request_metadata.set({})
```

### Flask Integration

```python
"""Flask middleware for request context."""

from flask import Flask, request, g
from request_context import RequestContext, get_request_id

app = Flask(__name__)


@app.before_request
def before_request():
    """Initialize request context before each request."""
    context = RequestContext.from_headers(
        dict(request.headers),
        method=request.method,
        path=request.path,
    )
    g.request_context = context


@app.after_request
def after_request(response):
    """Add request ID to response headers."""
    if hasattr(g, "request_context"):
        for key, value in g.request_context.to_headers().items():
            response.headers[key] = value
    return response


@app.route("/api/example")
def example():
    # Request ID is available anywhere
    request_id = get_request_id()
    return {"request_id": request_id}
```

### FastAPI Integration

```python
"""FastAPI middleware for request context."""

from fastapi import FastAPI, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from request_context import RequestContext, clear_context

app = FastAPI()


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Initialize context
        context = RequestContext.from_headers(
            dict(request.headers),
            method=request.method,
            path=request.url.path,
        )

        try:
            response = await call_next(request)

            # Add headers to response
            for key, value in context.to_headers().items():
                response.headers[key] = value

            return response
        finally:
            clear_context()


app.add_middleware(RequestContextMiddleware)


@app.get("/api/example")
async def example():
    from request_context import get_request_id
    return {"request_id": get_request_id()}
```

## Usage

### Basic Usage

```python
from request_context import (
    RequestContext,
    get_request_id,
    get_request_id_safe,
)

# Initialize at request start
context = RequestContext.init()
print(f"Request ID: {context.request_id}")

# Access anywhere in code
def some_function():
    request_id = get_request_id()
    print(f"Processing request: {request_id}")

some_function()  # Prints the same request ID
```

### With Logging

```python
import logging
from request_context import get_request_id_safe

logger = logging.getLogger(__name__)


def log_with_context(level: str, message: str, **extra):
    """Log with automatic request ID."""
    request_id = get_request_id_safe()
    log_func = getattr(logger, level)
    log_func(message, extra={
        "json_fields": {
            "request_id": request_id,
            **extra,
        }
    })


# Usage
log_with_context("info", "Processing order", order_id="123")
```

### Async Code

```python
import asyncio
from request_context import RequestContext, get_request_id


async def async_task():
    """Context is automatically available in async tasks."""
    await asyncio.sleep(0.1)
    print(f"In async task: {get_request_id()}")


async def main():
    context = RequestContext.init()

    # Context propagates to async tasks
    await asyncio.gather(
        async_task(),
        async_task(),
        async_task(),
    )

asyncio.run(main())
```

### Propagating to External Calls

```python
import requests
from request_context import get_request_id, get_correlation_id


def call_downstream_service(url: str, data: dict) -> dict:
    """Call downstream service with context propagation."""
    headers = {}

    request_id = get_request_id()
    if request_id:
        headers["X-Request-ID"] = request_id

    correlation_id = get_correlation_id()
    if correlation_id:
        headers["X-Correlation-ID"] = correlation_id

    response = requests.post(url, json=data, headers=headers)
    return response.json()
```

## Testing

```python
import pytest
from request_context import (
    RequestContext,
    get_request_id,
    clear_context,
)


@pytest.fixture(autouse=True)
def clean_context():
    """Clear context between tests."""
    clear_context()
    yield
    clear_context()


def test_request_id_generation():
    """Test automatic request ID generation."""
    context = RequestContext.init()
    assert context.request_id is not None
    assert len(context.request_id) == 36  # UUID format


def test_request_id_from_header():
    """Test request ID extraction from headers."""
    headers = {"X-Request-ID": "custom-id-123"}
    context = RequestContext.from_headers(headers)
    assert context.request_id == "custom-id-123"


def test_context_propagation():
    """Test context is available in nested functions."""
    context = RequestContext.init()

    def inner_function():
        return get_request_id()

    assert inner_function() == context.request_id


def test_elapsed_time():
    """Test elapsed time calculation."""
    import time
    context = RequestContext.init()
    time.sleep(0.1)
    elapsed = context.elapsed_ms()
    assert elapsed is not None
    assert elapsed >= 100


def test_context_isolation():
    """Test context is isolated between threads."""
    from concurrent.futures import ThreadPoolExecutor

    def thread_work(n: int) -> str:
        context = RequestContext.init(request_id=f"thread-{n}")
        return get_request_id()

    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(thread_work, range(10)))

    assert results == [f"thread-{i}" for i in range(10)]


@pytest.mark.asyncio
async def test_async_context():
    """Test context works with async."""
    import asyncio

    context = RequestContext.init()

    async def async_check():
        await asyncio.sleep(0.01)
        return get_request_id()

    results = await asyncio.gather(async_check(), async_check())

    assert all(r == context.request_id for r in results)
```

## Best Practices

### Do's

- Initialize context at request start
- Clear context at request end (if not using middleware)
- Propagate context to downstream services
- Use `get_request_id_safe()` when ID might not be set

### Don'ts

- Don't use thread-local for async code
- Don't assume context is always set
- Don't store sensitive data in context
- Don't forget to add to response headers

## Dependencies

```toml
# pyproject.toml - No additional dependencies!
# Uses only Python standard library
```

## References

- [Python contextvars](https://docs.python.org/3/library/contextvars.html)
- [PEP 567 - Context Variables](https://peps.python.org/pep-0567/)
- [Distributed Tracing](https://opentracing.io/docs/overview/what-is-tracing/)
