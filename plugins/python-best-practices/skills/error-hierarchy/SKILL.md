---
name: error-hierarchy
description: Exception hierarchy with TransientError and PermanentError for retry control. Triggers on 'error hierarchy', 'exception pattern', 'transient error', 'permanent error', 'retry pattern'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Error Hierarchy Pattern

Exception hierarchy with TransientError and PermanentError for intelligent retry control and error classification.

## Overview

```text
Exception occurs
       │
       ▼
┌──────┴──────┐
│  Classify   │
│   Error     │
└──────┬──────┘
       │
       ├── TransientError ──► Retry with backoff
       │   (temporary failures that may succeed on retry)
       │
       ├── PermanentError ──► Fail immediately
       │   (permanent failures that won't succeed on retry)
       │
       └── Unknown ──► Retry (conservative approach)
```

## Why This Pattern?

| Error Type | Retry? | Examples |
|------------|--------|----------|
| TransientError | Yes | Network timeout, rate limit, temp unavailable |
| PermanentError | No | Invalid input, auth failure, not found |
| Unknown | Yes | Safety net for unexpected errors |

## Implementation

### exceptions.py

```python
"""
Exception hierarchy for retry control.

This pattern classifies errors to determine retry behavior:
- TransientError: Temporary failures, should retry
- PermanentError: Permanent failures, should not retry
"""

from typing import Any


class ServiceError(Exception):
    """
    Base exception for all service errors.

    Attributes:
        message: Error message
        context: Additional context as key-value pairs
    """

    def __init__(self, message: str, **context: Any):
        super().__init__(message)
        self.message = message
        self.context = context

    def to_dict(self) -> dict[str, Any]:
        """Convert error to dictionary for logging/serialization."""
        return {
            "error_type": type(self).__name__,
            "message": self.message,
            **self.context,
        }

    def __str__(self) -> str:
        if self.context:
            context_str = ", ".join(f"{k}={v}" for k, v in self.context.items())
            return f"{self.message} ({context_str})"
        return self.message


class TransientError(ServiceError):
    """
    Transient error that should be retried.

    These errors are temporary and may succeed on retry:
    - Network timeouts
    - Rate limiting (429)
    - Service unavailable (503)
    - Connection refused
    - Temporary resource exhaustion

    Attributes:
        retry_after: Suggested seconds to wait before retry
    """

    def __init__(
        self,
        message: str,
        retry_after: int | None = None,
        **context: Any,
    ):
        super().__init__(message, **context)
        self.retry_after = retry_after


class PermanentError(ServiceError):
    """
    Permanent error that should not be retried.

    These errors will not succeed on retry:
    - Invalid input (400)
    - Unauthorized (401)
    - Forbidden (403)
    - Not found (404)
    - Validation failures
    - Business rule violations
    """
    pass


# Common error types
class ValidationError(PermanentError):
    """Input validation failed."""
    pass


class NotFoundError(PermanentError):
    """Resource not found."""
    pass


class AuthenticationError(PermanentError):
    """Authentication failed."""
    pass


class AuthorizationError(PermanentError):
    """Authorization failed (forbidden)."""
    pass


class ConflictError(PermanentError):
    """Resource conflict (e.g., duplicate)."""
    pass


class RateLimitError(TransientError):
    """Rate limit exceeded."""

    def __init__(self, message: str = "Rate limit exceeded", retry_after: int = 60, **context):
        super().__init__(message, retry_after=retry_after, **context)


class TimeoutError(TransientError):
    """Operation timed out."""
    pass


class ConnectionError(TransientError):
    """Connection failed."""
    pass


class ServiceUnavailableError(TransientError):
    """Service temporarily unavailable."""
    pass
```

### retry.py - Retry Decorator

```python
"""
Retry decorator with exponential backoff.
"""

import logging
import random
import time
from functools import wraps
from typing import Callable, TypeVar

from exceptions import TransientError, PermanentError

logger = logging.getLogger(__name__)
T = TypeVar("T")


def retry(
    max_attempts: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0,
    jitter: bool = True,
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    """
    Retry decorator with exponential backoff.

    Only retries TransientError. PermanentError and other
    exceptions are re-raised immediately.

    Args:
        max_attempts: Maximum number of attempts
        base_delay: Initial delay in seconds
        max_delay: Maximum delay in seconds
        exponential_base: Base for exponential backoff
        jitter: Add random jitter to prevent thundering herd

    Example:
        @retry(max_attempts=3, base_delay=1.0)
        def call_external_api():
            response = requests.get(url)
            if response.status_code == 429:
                raise RateLimitError()
            return response.json()
    """
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @wraps(func)
        def wrapper(*args, **kwargs) -> T:
            last_exception: Exception | None = None

            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)

                except PermanentError:
                    # Don't retry permanent errors
                    raise

                except TransientError as e:
                    last_exception = e

                    if attempt == max_attempts:
                        logger.error(
                            f"Max retries ({max_attempts}) exceeded for {func.__name__}",
                            extra={"json_fields": e.to_dict()},
                        )
                        raise

                    # Calculate delay
                    if e.retry_after:
                        delay = e.retry_after
                    else:
                        delay = min(
                            base_delay * (exponential_base ** (attempt - 1)),
                            max_delay,
                        )

                    if jitter:
                        delay = delay * (0.5 + random.random())

                    logger.warning(
                        f"Transient error in {func.__name__}, "
                        f"retrying in {delay:.2f}s (attempt {attempt}/{max_attempts})",
                        extra={"json_fields": e.to_dict()},
                    )

                    time.sleep(delay)

                except Exception as e:
                    # Unknown errors - treat as transient for safety
                    last_exception = e

                    if attempt == max_attempts:
                        raise

                    delay = min(
                        base_delay * (exponential_base ** (attempt - 1)),
                        max_delay,
                    )

                    if jitter:
                        delay = delay * (0.5 + random.random())

                    logger.warning(
                        f"Unexpected error in {func.__name__}, "
                        f"retrying in {delay:.2f}s (attempt {attempt}/{max_attempts}): {e}",
                    )

                    time.sleep(delay)

            # Should not reach here, but just in case
            if last_exception:
                raise last_exception
            raise RuntimeError("Unexpected retry loop exit")

        return wrapper
    return decorator
```

### error_handler.py - HTTP Error Handling

```python
"""
Error handling for HTTP APIs.
"""

from flask import Flask, jsonify
from exceptions import (
    ServiceError,
    TransientError,
    PermanentError,
    ValidationError,
    NotFoundError,
    AuthenticationError,
    AuthorizationError,
)

app = Flask(__name__)


def error_to_http_status(error: Exception) -> int:
    """Map error to HTTP status code."""
    if isinstance(error, ValidationError):
        return 400
    if isinstance(error, AuthenticationError):
        return 401
    if isinstance(error, AuthorizationError):
        return 403
    if isinstance(error, NotFoundError):
        return 404
    if isinstance(error, PermanentError):
        return 400  # Generic client error
    if isinstance(error, TransientError):
        return 503  # Service unavailable, client can retry
    return 500  # Unknown error


@app.errorhandler(ServiceError)
def handle_service_error(error: ServiceError):
    """Handle all service errors."""
    status_code = error_to_http_status(error)

    response = {
        "error": {
            "type": type(error).__name__,
            "message": error.message,
        }
    }

    # Add retry-after header for transient errors
    headers = {}
    if isinstance(error, TransientError) and error.retry_after:
        headers["Retry-After"] = str(error.retry_after)

    return jsonify(response), status_code, headers


@app.errorhandler(Exception)
def handle_unexpected_error(error: Exception):
    """Handle unexpected errors."""
    # Log the full error for debugging
    app.logger.exception("Unexpected error")

    return jsonify({
        "error": {
            "type": "InternalError",
            "message": "An unexpected error occurred",
        }
    }), 500
```

## Usage

### Basic Usage

```python
from exceptions import (
    TransientError,
    PermanentError,
    ValidationError,
    RateLimitError,
)

def process_order(order_data: dict) -> dict:
    # Validation - permanent error
    if not order_data.get("items"):
        raise ValidationError("Order must have items", order_id=order_data.get("id"))

    # External call that might fail temporarily
    try:
        inventory = check_inventory(order_data["items"])
    except ConnectionError:
        raise TransientError("Inventory service unavailable")

    return create_order(order_data, inventory)
```

### With Retry Decorator

```python
from exceptions import RateLimitError, ServiceUnavailableError
from retry import retry


@retry(max_attempts=3, base_delay=1.0)
def call_payment_api(payment_data: dict) -> dict:
    response = requests.post(PAYMENT_URL, json=payment_data)

    if response.status_code == 429:
        retry_after = int(response.headers.get("Retry-After", 60))
        raise RateLimitError(retry_after=retry_after)

    if response.status_code == 503:
        raise ServiceUnavailableError("Payment service unavailable")

    if response.status_code >= 400:
        raise PermanentError(f"Payment failed: {response.text}")

    return response.json()
```

### Error Classification Helper

```python
def classify_http_error(status_code: int, message: str) -> ServiceError:
    """Classify HTTP error into appropriate exception type."""
    if status_code == 400:
        return ValidationError(message)
    elif status_code == 401:
        return AuthenticationError(message)
    elif status_code == 403:
        return AuthorizationError(message)
    elif status_code == 404:
        return NotFoundError(message)
    elif status_code == 429:
        return RateLimitError(message)
    elif status_code == 503:
        return ServiceUnavailableError(message)
    elif status_code >= 500:
        return TransientError(message)  # Server errors are usually transient
    else:
        return PermanentError(message)


# Usage
response = requests.get(url)
if not response.ok:
    raise classify_http_error(response.status_code, response.text)
```

## Error Context

```python
# Include context for debugging
raise ValidationError(
    "Invalid order amount",
    order_id="ORD-123",
    amount=-50.00,
    currency="USD",
)

# Access context
try:
    process_order(data)
except ServiceError as e:
    logger.error("Order failed", extra={"json_fields": e.to_dict()})
    # Logs: {"error_type": "ValidationError", "message": "...", "order_id": "ORD-123", ...}
```

## Testing

```python
import pytest
from exceptions import (
    TransientError,
    PermanentError,
    ValidationError,
    RateLimitError,
)
from retry import retry


def test_transient_error_has_retry_after():
    error = RateLimitError(retry_after=120)
    assert error.retry_after == 120


def test_error_to_dict():
    error = ValidationError("Invalid input", field="email")
    d = error.to_dict()

    assert d["error_type"] == "ValidationError"
    assert d["message"] == "Invalid input"
    assert d["field"] == "email"


def test_retry_succeeds_after_transient():
    attempts = []

    @retry(max_attempts=3, base_delay=0.01)
    def flaky_function():
        attempts.append(1)
        if len(attempts) < 2:
            raise TransientError("Temporary failure")
        return "success"

    result = flaky_function()
    assert result == "success"
    assert len(attempts) == 2


def test_retry_fails_on_permanent():
    @retry(max_attempts=3, base_delay=0.01)
    def permanent_failure():
        raise PermanentError("Invalid input")

    with pytest.raises(PermanentError):
        permanent_failure()
```

## Best Practices

### Do's

- Classify errors early at boundaries
- Include context for debugging
- Use retry_after when available
- Log errors with context

### Don'ts

- Don't catch Exception broadly
- Don't retry permanent errors
- Don't ignore error context
- Don't create too deep hierarchies

## Dependencies

```toml
# pyproject.toml - No additional dependencies!
# Uses only Python standard library
```

## References

- [HTTP Status Codes](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status)
- [Retry Pattern](https://docs.microsoft.com/en-us/azure/architecture/patterns/retry)
- [Exponential Backoff](https://en.wikipedia.org/wiki/Exponential_backoff)
