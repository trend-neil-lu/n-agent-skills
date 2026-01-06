---
name: gcp-config
description: GCP-aware configuration with Metadata Server integration and thread-safe singleton. Triggers on 'gcp config', 'metadata server', 'gcp configuration', 'google cloud config'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# GCP Configuration Management

Thread-safe configuration management with GCP metadata server integration and dataclass-based validation.

## Overview

```text
Configuration Sources (Priority Order)
       │
       ├── 1. GCP Metadata Server (Cloud Run auto-detection)
       ├── 2. Environment Variables (explicit config)
       └── 3. Defaults (fallback values)
       │
       ▼
Config Dataclass
       │
       ├── Validation (__post_init__)
       ├── Computed fields
       └── Thread-safe singleton
       │
       ▼
Application
```

## Why This Pattern?

| Feature | Benefit |
|---------|---------|
| GCP Metadata Server | Auto-detect project_id, region in Cloud Run |
| Thread-safe singleton | Safe for multi-threaded/async apps |
| Dataclass validation | Type-safe, IDE-friendly, self-documenting |
| Environment fallbacks | Works in local development |

## Implementation

### exceptions.py

```python
"""Configuration exceptions."""


class ConfigurationError(Exception):
    """Raised when configuration is invalid or missing."""
    pass
```

### config.py

```python
"""
Configuration management for GCP Cloud Run services.

Features:
- GCP Metadata Server integration for auto-detection
- Thread-safe singleton pattern
- Dataclass-based configuration with validation
- Environment variable fallbacks for local development
"""

import logging
import os
import threading
import urllib.request
from dataclasses import dataclass
from urllib.error import URLError

from exceptions import ConfigurationError

logger = logging.getLogger(__name__)


def _get_metadata(path: str, timeout: float = 1.0) -> str | None:
    """
    Get value from GCP metadata server.

    The metadata server is available at metadata.google.internal
    and provides instance/project information without credentials.

    Args:
        path: Metadata path (e.g., "project/project-id")
        timeout: Request timeout in seconds

    Returns:
        Metadata value or None if unavailable
    """
    try:
        url = f"http://metadata.google.internal/computeMetadata/v1/{path}"
        req = urllib.request.Request(url, headers={"Metadata-Flavor": "Google"})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.read().decode("utf-8").strip()
    except (URLError, TimeoutError, Exception):
        return None


def _get_gcp_project_id() -> str:
    """
    Get GCP project ID with fallback chain.

    Priority:
    1. GCP Metadata Server (Cloud Run)
    2. GCP_PROJECT_ID environment variable
    3. GOOGLE_CLOUD_PROJECT environment variable (gcloud default)

    Raises:
        ConfigurationError: If project ID cannot be determined
    """
    # 1. Metadata Server (preferred in Cloud Run)
    project_id = _get_metadata("project/project-id")
    if project_id:
        return project_id

    # 2. Standard environment variable
    project_id = os.getenv("GCP_PROJECT_ID")
    if project_id:
        return project_id

    # 3. gcloud default
    project_id = os.getenv("GOOGLE_CLOUD_PROJECT")
    if project_id:
        return project_id

    raise ConfigurationError("GCP project ID not found")


def _get_region() -> str:
    """
    Get GCP region with fallback chain.

    Priority:
    1. GCP Metadata Server (Cloud Run)
    2. REGION or CLOUD_RUN_REGION environment variable

    Raises:
        ConfigurationError: If region cannot be determined
    """
    # 1. Metadata Server (preferred in Cloud Run)
    # Returns format: projects/PROJECT_NUM/regions/REGION
    region_path = _get_metadata("instance/region")
    if region_path:
        return region_path.split("/")[-1]

    # 2. Environment variables
    region = os.getenv("REGION") or os.getenv("CLOUD_RUN_REGION")
    if region:
        return region

    raise ConfigurationError("Region not found")


def _require(key: str) -> str:
    """
    Get required environment variable.

    Args:
        key: Environment variable name

    Raises:
        ConfigurationError: If variable is not set

    Returns:
        Environment variable value
    """
    value = os.getenv(key)
    if not value:
        raise ConfigurationError(f"Required environment variable {key} not set")
    return value


def _get_bool_env(key: str, default: bool = True) -> bool:
    """
    Get boolean from environment variable.

    Accepts: true, 1, yes, on (case-insensitive)

    Args:
        key: Environment variable name
        default: Default value if not set

    Returns:
        Boolean value
    """
    val = os.getenv(key, str(default)).lower()
    return val in ("true", "1", "yes", "on")


def _get_float_env(
    key: str,
    default: float,
    min_val: float = 0.0,
    max_val: float = 1.0
) -> float:
    """
    Get float from environment variable with bounds checking.

    Args:
        key: Environment variable name
        default: Default value if not set
        min_val: Minimum allowed value
        max_val: Maximum allowed value

    Returns:
        Float value clamped to [min_val, max_val]
    """
    val_str = os.getenv(key)
    if val_str is None:
        return default
    try:
        val = float(val_str)
        return max(min_val, min(max_val, val))  # Clamp to valid range
    except ValueError:
        logger.warning(f"Invalid {key} value '{val_str}', using default {default}")
        return default


def _get_int_env(key: str, default: int) -> int:
    """
    Get integer from environment variable.

    Args:
        key: Environment variable name
        default: Default value if not set

    Returns:
        Integer value
    """
    val_str = os.getenv(key)
    if val_str is None:
        return default
    try:
        return int(val_str)
    except ValueError:
        logger.warning(f"Invalid {key} value '{val_str}', using default {default}")
        return default


@dataclass
class Config:
    """
    Application configuration container.

    Uses dataclass for type safety and automatic __init__, __repr__.
    Validation is performed in __post_init__.
    """

    # GCP Configuration
    gcp_project_id: str
    region: str

    # Application-specific
    log_level: str

    # Cloud Run Metadata (auto-injected by Cloud Run)
    service_name: str | None
    revision: str | None

    # Feature flags
    metrics_enabled: bool
    tracing_enabled: bool

    # Tuning parameters
    trace_sampling_ratio: float  # 0.0 to 1.0

    # Version (from version.json)
    version: str

    def __post_init__(self):
        """Validate configuration after initialization."""
        self._validate()
        self._log_config()

    def _validate(self) -> None:
        """Validate configuration values."""
        # Validate log level
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if self.log_level.upper() not in valid_levels:
            raise ConfigurationError(f"Invalid LOG_LEVEL: {self.log_level}")

        # Validate sampling ratio
        if not 0.0 <= self.trace_sampling_ratio <= 1.0:
            raise ConfigurationError(
                f"TRACE_SAMPLING_RATIO must be 0.0-1.0, got: {self.trace_sampling_ratio}"
            )

    def _log_config(self) -> None:
        """Log configuration for debugging."""
        logger.debug(
            "Configuration loaded",
            extra={
                "json_fields": {
                    "gcp_project_id": self.gcp_project_id,
                    "region": self.region,
                    "log_level": self.log_level,
                    "metrics_enabled": self.metrics_enabled,
                    "tracing_enabled": self.tracing_enabled,
                    "trace_sampling_ratio": self.trace_sampling_ratio,
                    "version": self.version,
                    "service_name": self.service_name,
                    "revision": self.revision,
                }
            },
        )

    @property
    def is_cloud_run(self) -> bool:
        """Check if running in Cloud Run environment."""
        return self.service_name is not None


# Thread-safe singleton
_config: Config | None = None
_config_lock = threading.Lock()


def get_config() -> Config:
    """
    Get or create configuration instance (thread-safe).

    Uses double-checked locking pattern for efficiency.

    Returns:
        Singleton Config instance
    """
    global _config
    if _config is not None:
        return _config

    with _config_lock:
        # Double-check after acquiring lock
        if _config is not None:
            return _config

        k_service = os.getenv("K_SERVICE")
        is_cloud_run = k_service is not None

        # Observability enabled only in Cloud Run (default True)
        tracing_enabled = is_cloud_run and _get_bool_env("TRACING_ENABLED", True)
        metrics_enabled = is_cloud_run and _get_bool_env("METRICS_ENABLED", True)

        # Trace sampling ratio (default 5% for cost control)
        trace_sampling_ratio = _get_float_env("TRACE_SAMPLING_RATIO", default=0.05)

        # Get version from version.json
        from my_module import __version__

        _config = Config(
            gcp_project_id=_get_gcp_project_id(),
            region=_get_region(),
            log_level=os.getenv("LOG_LEVEL", "INFO"),
            service_name=k_service,
            revision=os.getenv("K_REVISION"),
            version=__version__,
            metrics_enabled=metrics_enabled,
            tracing_enabled=tracing_enabled,
            trace_sampling_ratio=trace_sampling_ratio,
        )
        return _config


def reset_config() -> None:
    """
    Reset configuration singleton.

    For testing purposes only.
    """
    global _config
    with _config_lock:
        _config = None
```

## Usage

### Basic Usage

```python
from config import get_config

config = get_config()

# Access configuration
print(f"Project: {config.gcp_project_id}")
print(f"Region: {config.region}")
print(f"Service: {config.service_name}")
print(f"Version: {config.version}")

# Check environment
if config.is_cloud_run:
    print("Running in Cloud Run")
else:
    print("Running locally")
```

### With Logging Integration

```python
from config import get_config
from logging_module import (
    setup_cloud_logging,
    set_gcp_project_id,
    set_service_version,
)

# Initialize
config = get_config()
setup_cloud_logging(config.log_level)
set_gcp_project_id(config.gcp_project_id)
set_service_version(config.version)
```

### With Observability

```python
from config import get_config
from observability import setup_tracing

config = get_config()

if config.tracing_enabled:
    setup_tracing(
        service_name=config.service_name or "local-dev",
        project_id=config.gcp_project_id,
        sampling_ratio=config.trace_sampling_ratio,
    )
```

## Adding Custom Configuration

### Extend the Config Dataclass

```python
@dataclass
class Config:
    # ... existing fields ...

    # Custom fields
    api_key: str
    max_workers: int
    timeout_seconds: int
    feature_flag_enabled: bool


def get_config() -> Config:
    # ... existing logic ...

    _config = Config(
        # ... existing fields ...

        # Custom fields
        api_key=_require("API_KEY"),  # Required
        max_workers=_get_int_env("MAX_WORKERS", default=4),
        timeout_seconds=_get_int_env("TIMEOUT_SECONDS", default=30),
        feature_flag_enabled=_get_bool_env("FEATURE_FLAG_ENABLED", False),
    )
    return _config
```

### Add Validation

```python
def _validate(self) -> None:
    # ... existing validation ...

    # Custom validation
    if self.max_workers < 1:
        raise ConfigurationError("MAX_WORKERS must be >= 1")

    if self.timeout_seconds < 1 or self.timeout_seconds > 300:
        raise ConfigurationError("TIMEOUT_SECONDS must be 1-300")
```

## Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GCP_PROJECT_ID` | GCP Project ID (auto-detected in Cloud Run) | `my-project` |
| `REGION` | GCP Region (auto-detected in Cloud Run) | `asia-east1` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `INFO` | Logging level |
| `TRACING_ENABLED` | `true` | Enable OpenTelemetry tracing |
| `METRICS_ENABLED` | `true` | Enable metrics collection |
| `TRACE_SAMPLING_RATIO` | `0.05` | Trace sampling ratio (0.0-1.0) |

### Cloud Run Auto-Injected

| Variable | Description |
|----------|-------------|
| `K_SERVICE` | Cloud Run service name |
| `K_REVISION` | Cloud Run revision name |
| `K_CONFIGURATION` | Cloud Run configuration name |
| `PORT` | Port to listen on (default 8080) |

## Testing

### Unit Tests

```python
import os
import pytest
from config import get_config, reset_config, ConfigurationError


@pytest.fixture(autouse=True)
def reset_config_fixture():
    """Reset config between tests."""
    reset_config()
    yield
    reset_config()


def test_get_config_local(monkeypatch):
    """Test configuration in local environment."""
    monkeypatch.setenv("GCP_PROJECT_ID", "test-project")
    monkeypatch.setenv("REGION", "us-central1")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")

    config = get_config()

    assert config.gcp_project_id == "test-project"
    assert config.region == "us-central1"
    assert config.log_level == "DEBUG"
    assert config.is_cloud_run is False


def test_get_config_cloud_run(monkeypatch):
    """Test configuration in Cloud Run environment."""
    monkeypatch.setenv("GCP_PROJECT_ID", "prod-project")
    monkeypatch.setenv("REGION", "asia-east1")
    monkeypatch.setenv("K_SERVICE", "my-service")
    monkeypatch.setenv("K_REVISION", "my-service-00001")

    config = get_config()

    assert config.service_name == "my-service"
    assert config.revision == "my-service-00001"
    assert config.is_cloud_run is True
    assert config.tracing_enabled is True


def test_get_config_singleton():
    """Test that get_config returns singleton."""
    config1 = get_config()
    config2 = get_config()

    assert config1 is config2


def test_missing_required_env():
    """Test error on missing required variable."""
    with pytest.raises(ConfigurationError):
        get_config()  # No GCP_PROJECT_ID set


def test_invalid_log_level(monkeypatch):
    """Test error on invalid log level."""
    monkeypatch.setenv("GCP_PROJECT_ID", "test")
    monkeypatch.setenv("REGION", "us-central1")
    monkeypatch.setenv("LOG_LEVEL", "INVALID")

    with pytest.raises(ConfigurationError):
        get_config()
```

## Best Practices

### Do's

- Use `get_config()` everywhere (singleton pattern)
- Validate in `__post_init__` for early failure
- Provide sensible defaults for optional values
- Log configuration at startup for debugging
- Use type hints for IDE support

### Don'ts

- Don't access `os.getenv()` directly in application code
- Don't create multiple Config instances
- Don't store secrets in environment variables (use Secret Manager)
- Don't skip validation

## GCP Metadata Server Paths

| Path | Returns |
|------|---------|
| `project/project-id` | GCP Project ID |
| `project/numeric-project-id` | Numeric Project ID |
| `instance/region` | `projects/NUM/regions/REGION` |
| `instance/zone` | `projects/NUM/zones/ZONE` |
| `instance/service-accounts/default/token` | Access token |

## Dependencies

```toml
# pyproject.toml - No additional dependencies needed!
# Uses only Python standard library
```

## References

- [Cloud Run Environment Variables](https://cloud.google.com/run/docs/container-contract#env-vars)
- [GCP Metadata Server](https://cloud.google.com/compute/docs/metadata/overview)
- [Python Dataclasses](https://docs.python.org/3/library/dataclasses.html)
