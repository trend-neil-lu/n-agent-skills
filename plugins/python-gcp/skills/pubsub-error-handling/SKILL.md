---
name: pubsub-error-handling
description: Error hierarchy for Pub/Sub push retry control with TransientError and PermanentError. Triggers on 'pubsub error', 'pubsub retry', 'cloud pubsub error handling', 'gcp error handling'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Pub/Sub Error Handling

Error classification pattern for controlling Pub/Sub push retry behavior with TransientError and PermanentError hierarchy.

## Overview

```text
Exception occurs
       │
       ▼
┌──────┴──────┐
│  Exception  │
│    Type     │
└──────┬──────┘
       │
       ├── TransientError ──► HTTP 500 ──► Pub/Sub retries
       │                                   (exponential backoff)
       │
       ├── PermanentError ──► HTTP 400 ──► No retry
       │                      (publish error result)
       │
       └── Unknown Error ────► HTTP 500 ──► Pub/Sub retries
                               (treat as transient)
```

## Why This Pattern?

| Error Type | HTTP Status | Pub/Sub Behavior | Use Case |
|------------|-------------|------------------|----------|
| TransientError | 500 | Retries with backoff | Network timeout, rate limiting |
| PermanentError | 400 | No retry | Invalid input, auth failure |
| ValidationError | 400 | No retry | Bad request format |
| Unknown | 500 | Retries | Safety net for unexpected errors |

## Implementation

### exceptions.py

```python
"""
Exception hierarchy for proper retry handling.

This module defines error classification for Pub/Sub push:
- TransientError: Temporary failures that should be retried
- PermanentError: Permanent failures that should not be retried
"""


class ServiceError(Exception):
    """
    Base exception for all service errors.

    All custom exceptions should inherit from this class.
    """
    pass


class TransientError(ServiceError):
    """
    Transient error that should be retried.

    These errors are temporary and may succeed on retry. When raised,
    the handler returns HTTP 500, triggering Pub/Sub's automatic retry
    with exponential backoff.

    Examples:
        - Network errors (connection timeout, DNS failure)
        - GCS transient errors (503, rate limiting)
        - Database connection failures
        - Memory pressure (might resolve after retry)
        - Timeout errors
        - Temporary service unavailability
    """
    pass


class PermanentError(ServiceError):
    """
    Permanent error that should not be retried.

    These errors will not succeed on retry. When raised, the handler
    publishes an error result and returns HTTP 400, preventing
    Pub/Sub from retrying.

    Examples:
        - Invalid file format
        - File not found (404)
        - Permission denied (403)
        - File size exceeds limit
        - Malformed request
        - License validation failures
    """
    pass


class ConfigurationError(PermanentError):
    """
    Configuration validation error.

    Raised when required configuration is missing or invalid.
    This is permanent - retrying won't help.
    """
    pass


class ValidationError(PermanentError):
    """
    Request/event validation error.

    Raised when input data is malformed or missing required fields.
    This is permanent - the same message will always fail.
    """
    pass


class SecurityError(PermanentError):
    """
    Security check failure.

    Raised when authentication or authorization fails.
    """
    pass


class RateLimitError(TransientError):
    """
    Rate limit exceeded.

    Raised when API rate limits are hit. Retrying after backoff
    should succeed.
    """
    pass


class TimeoutError(TransientError):
    """
    Operation timeout.

    Raised when an operation takes too long. Retrying may succeed
    if the system is less loaded.
    """
    pass


class NetworkError(TransientError):
    """
    Network connectivity error.

    Raised for connection failures, DNS issues, etc.
    Usually transient and will succeed on retry.
    """
    pass
```

### HTTP Handler Pattern

```python
"""HTTP handler with error classification."""

from flask import Flask, Request
from exceptions import (
    TransientError,
    PermanentError,
    ValidationError,
)
import logging

logger = logging.getLogger(__name__)
app = Flask(__name__)


def process_message(data: dict) -> dict:
    """
    Process a Pub/Sub message.

    Raises:
        ValidationError: If message format is invalid
        PermanentError: If processing fails permanently
        TransientError: If processing fails temporarily
    """
    # Validation
    if "id" not in data:
        raise ValidationError("Missing required field: id")

    # Business logic that might fail
    try:
        result = do_work(data)
        return result
    except ConnectionError as e:
        # Network issues are transient
        raise TransientError(f"Connection failed: {e}") from e
    except PermissionError as e:
        # Permission issues are permanent
        raise PermanentError(f"Permission denied: {e}") from e


@app.route("/", methods=["POST"])
def handler(request: Request) -> tuple[str, int]:
    """
    HTTP handler for Pub/Sub push.

    Returns:
        Tuple of (response_body, status_code)
        - 200: Success (message acknowledged)
        - 400: Permanent error (message acknowledged, no retry)
        - 500: Transient error (message nack'd, will retry)
    """
    try:
        # Parse and validate
        data = parse_pubsub_message(request)

        # Process
        result = process_message(data)

        # Success
        logger.info("Message processed successfully", extra={
            "json_fields": {"message_id": data.get("id")}
        })
        return "OK", 200

    except ValidationError as e:
        # Validation error - permanent, don't retry
        logger.warning(f"Validation error: {e}", extra={
            "json_fields": {
                "error_type": "ValidationError",
                "error_message": str(e),
            }
        })
        return f"Validation error: {e}", 400

    except PermanentError as e:
        # Permanent error - publish error result, don't retry
        logger.error(f"Permanent error: {e}", extra={
            "json_fields": {
                "error_type": type(e).__name__,
                "error_message": str(e),
            }
        })
        # Optionally publish error result to dead letter topic
        publish_error_result(e)
        return f"Permanent error: {e}", 400

    except TransientError as e:
        # Transient error - retry
        logger.error(f"Transient error: {e}", extra={
            "json_fields": {
                "error_type": type(e).__name__,
                "error_message": str(e),
            }
        })
        return f"Transient error: {e}", 500

    except Exception as e:
        # Unknown error - treat as transient for safety
        logger.exception(f"Unexpected error: {e}")
        return f"Internal error: {e}", 500
```

## Advanced Patterns

### Error Context

```python
class ServiceError(Exception):
    """Base exception with context support."""

    def __init__(self, message: str, **context):
        super().__init__(message)
        self.context = context

    def to_dict(self) -> dict:
        """Convert to dictionary for logging/serialization."""
        return {
            "error_type": type(self).__name__,
            "message": str(self),
            **self.context,
        }


class TransientError(ServiceError):
    """Transient error with retry hints."""

    def __init__(
        self,
        message: str,
        retry_after: int | None = None,
        **context
    ):
        super().__init__(message, **context)
        self.retry_after = retry_after


# Usage
raise TransientError(
    "Rate limit exceeded",
    retry_after=60,
    bucket="my-bucket",
    operation="download",
)
```

### Error Classification Helper

```python
def classify_gcs_error(error: Exception) -> ServiceError:
    """
    Classify GCS errors as transient or permanent.

    Args:
        error: Original GCS error

    Returns:
        Appropriate ServiceError subclass
    """
    from google.api_core.exceptions import (
        NotFound,
        Forbidden,
        TooManyRequests,
        ServiceUnavailable,
        DeadlineExceeded,
    )

    if isinstance(error, NotFound):
        return PermanentError(f"Object not found: {error}")
    elif isinstance(error, Forbidden):
        return PermanentError(f"Access denied: {error}")
    elif isinstance(error, TooManyRequests):
        return RateLimitError(f"Rate limit exceeded: {error}")
    elif isinstance(error, ServiceUnavailable):
        return TransientError(f"Service unavailable: {error}")
    elif isinstance(error, DeadlineExceeded):
        return TimeoutError(f"Deadline exceeded: {error}")
    else:
        # Unknown - treat as transient for safety
        return TransientError(f"GCS error: {error}")


# Usage
try:
    blob = bucket.blob(object_name)
    data = blob.download_as_bytes()
except Exception as e:
    raise classify_gcs_error(e) from e
```

### Business Exception vs System Error

```python
"""Distinguish expected failures from system errors."""

from dataclasses import dataclass
from enum import Enum


class ErrorCategory(Enum):
    """Error category for observability."""
    SYSTEM_ERROR = "system"      # Infrastructure failure
    BUSINESS_EXCEPTION = "business"  # Expected limitation
    CLIENT_ERROR = "client"      # Invalid input


@dataclass
class ErrorInfo:
    """Error information for logging and metrics."""
    category: ErrorCategory
    error_type: str
    message: str
    should_alert: bool = True


def categorize_error(error: Exception) -> ErrorInfo:
    """
    Categorize error for observability.

    Business exceptions (expected failures) should not trigger alerts.
    System errors (infrastructure failures) should trigger alerts.
    """
    if isinstance(error, ValidationError):
        return ErrorInfo(
            category=ErrorCategory.CLIENT_ERROR,
            error_type="ValidationError",
            message=str(error),
            should_alert=False,
        )

    if isinstance(error, PermanentError):
        # Check if it's a business exception
        if is_business_exception(error):
            return ErrorInfo(
                category=ErrorCategory.BUSINESS_EXCEPTION,
                error_type=type(error).__name__,
                message=str(error),
                should_alert=False,
            )
        else:
            return ErrorInfo(
                category=ErrorCategory.SYSTEM_ERROR,
                error_type=type(error).__name__,
                message=str(error),
                should_alert=True,
            )

    if isinstance(error, TransientError):
        return ErrorInfo(
            category=ErrorCategory.SYSTEM_ERROR,
            error_type=type(error).__name__,
            message=str(error),
            should_alert=True,
        )

    # Unknown
    return ErrorInfo(
        category=ErrorCategory.SYSTEM_ERROR,
        error_type=type(error).__name__,
        message=str(error),
        should_alert=True,
    )


def is_business_exception(error: Exception) -> bool:
    """
    Check if error is an expected business exception.

    Business exceptions:
    - File too large
    - Password protected
    - Unsupported format
    - etc.

    These are expected limitations, not system failures.
    """
    business_keywords = [
        "password protected",
        "file too large",
        "unsupported format",
        "limit exceeded",
    ]
    message = str(error).lower()
    return any(keyword in message for keyword in business_keywords)
```

### With OpenTelemetry

```python
"""Error handling with tracing integration."""

from opentelemetry import trace
from opentelemetry.trace import StatusCode

tracer = trace.get_tracer(__name__)


def process_with_tracing(data: dict) -> dict:
    """Process with proper span error handling."""
    span = trace.get_current_span()

    try:
        result = do_work(data)
        span.set_status(StatusCode.OK)
        return result

    except PermanentError as e:
        # Business exception - mark as expected
        span.set_attribute("error.expected", True)
        span.set_status(StatusCode.ERROR, str(e))
        raise

    except TransientError as e:
        # System error - record exception
        span.record_exception(e)
        span.set_status(StatusCode.ERROR, str(e))
        raise

    except Exception as e:
        # Unknown error - record full details
        span.record_exception(e)
        span.set_status(StatusCode.ERROR, f"Unexpected: {e}")
        raise
```

## Pub/Sub Configuration

### Subscription Settings

```yaml
# terraform or gcloud config
subscription:
  ackDeadlineSeconds: 600  # 10 minutes
  messageRetentionDuration: 604800s  # 7 days
  retryPolicy:
    minimumBackoff: 10s
    maximumBackoff: 600s  # 10 minutes
  deadLetterPolicy:
    deadLetterTopic: projects/PROJECT/topics/dead-letter
    maxDeliveryAttempts: 5
```

### Dead Letter Handling

```python
"""Publish to dead letter topic for failed messages."""

from google.cloud import pubsub_v1

publisher = pubsub_v1.PublisherClient()


def publish_to_dead_letter(
    original_message: dict,
    error: Exception,
    attempt_count: int,
) -> None:
    """
    Publish failed message to dead letter topic.

    Args:
        original_message: Original Pub/Sub message
        error: Error that caused the failure
        attempt_count: Number of delivery attempts
    """
    dead_letter_topic = "projects/PROJECT/topics/dead-letter"

    dead_letter_message = {
        "original_message": original_message,
        "error": {
            "type": type(error).__name__,
            "message": str(error),
        },
        "attempt_count": attempt_count,
        "timestamp": datetime.now(UTC).isoformat(),
    }

    publisher.publish(
        dead_letter_topic,
        json.dumps(dead_letter_message).encode("utf-8"),
    )
```

## Best Practices

### Do's

- Classify errors early (at the boundary)
- Include context in error messages
- Use specific exception types
- Log with structured context
- Distinguish business exceptions from system errors
- Configure dead letter for investigation

### Don'ts

- Don't catch and ignore errors
- Don't use generic Exception for business logic
- Don't retry permanent errors
- Don't log sensitive data in error messages
- Don't create deep exception hierarchies

## Testing

```python
import pytest
from exceptions import TransientError, PermanentError, ValidationError


def test_transient_error_retries():
    """Verify transient errors return 500."""
    with pytest.raises(TransientError):
        raise TransientError("Connection failed")


def test_permanent_error_no_retry():
    """Verify permanent errors return 400."""
    with pytest.raises(PermanentError):
        raise PermanentError("File not found")


def test_validation_is_permanent():
    """Verify ValidationError is a PermanentError."""
    error = ValidationError("Missing field")
    assert isinstance(error, PermanentError)


def test_error_context():
    """Verify error context is preserved."""
    error = TransientError("Rate limit", bucket="my-bucket")
    assert error.context["bucket"] == "my-bucket"
    assert "bucket" in error.to_dict()
```

## Dependencies

```toml
# pyproject.toml - No additional dependencies needed!
# Uses only Python standard library
```

## References

- [Pub/Sub Push Subscriptions](https://cloud.google.com/pubsub/docs/push)
- [Pub/Sub Retry Policy](https://cloud.google.com/pubsub/docs/handling-failures)
- [Dead Letter Topics](https://cloud.google.com/pubsub/docs/dead-letter-topics)
