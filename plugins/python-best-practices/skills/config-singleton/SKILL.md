---
name: config-singleton
description: Thread-safe singleton configuration pattern using dataclasses with validation. Triggers on 'config singleton', 'configuration pattern', 'dataclass config', 'environment config'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Configuration Singleton Pattern

Thread-safe singleton configuration using Python dataclasses with validation and environment variable support.

## Overview

```text
Environment Variables + Defaults
              │
              ▼
       get_config()
              │
              ├── First call: Create Config instance
              │   ├── Read environment variables
              │   ├── Apply defaults
              │   ├── Validate in __post_init__
              │   └── Store in global singleton
              │
              └── Subsequent calls: Return existing instance
              │
              ▼
         Config dataclass
              │
              ├── Type-safe access
              ├── IDE autocomplete
              └── Immutable after creation
```

## Why This Pattern?

| Feature | Benefit |
|---------|---------|
| Singleton | Consistent config across application |
| Thread-safe | Safe for multi-threaded apps |
| Dataclass | Type hints, IDE support, validation |
| Environment-based | 12-factor app compliant |

## Implementation

### config.py

```python
"""
Thread-safe singleton configuration with dataclass validation.

Features:
- Double-checked locking for thread safety
- Dataclass for type safety and validation
- Environment variable support with defaults
- Validation in __post_init__
"""

import logging
import os
import threading
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger(__name__)


class ConfigurationError(Exception):
    """Raised when configuration is invalid or missing."""
    pass


def _require(key: str) -> str:
    """
    Get required environment variable.

    Raises:
        ConfigurationError: If variable is not set
    """
    value = os.getenv(key)
    if not value:
        raise ConfigurationError(f"Required environment variable {key} not set")
    return value


def _get_bool(key: str, default: bool = False) -> bool:
    """
    Get boolean from environment variable.

    Accepts: true, 1, yes, on (case-insensitive)
    """
    val = os.getenv(key, str(default)).lower()
    return val in ("true", "1", "yes", "on")


def _get_int(key: str, default: int) -> int:
    """Get integer from environment variable."""
    val = os.getenv(key)
    if val is None:
        return default
    try:
        return int(val)
    except ValueError:
        logger.warning(f"Invalid {key}='{val}', using default {default}")
        return default


def _get_float(key: str, default: float) -> float:
    """Get float from environment variable."""
    val = os.getenv(key)
    if val is None:
        return default
    try:
        return float(val)
    except ValueError:
        logger.warning(f"Invalid {key}='{val}', using default {default}")
        return default


def _get_list(key: str, default: list[str] | None = None, sep: str = ",") -> list[str]:
    """
    Get list from environment variable.

    Example: ALLOWED_HOSTS=host1,host2,host3
    """
    val = os.getenv(key)
    if val is None:
        return default or []
    return [item.strip() for item in val.split(sep) if item.strip()]


@dataclass(frozen=True)
class Config:
    """
    Application configuration.

    Immutable after creation (frozen=True).
    Add your configuration fields here.
    """

    # Application
    app_name: str
    environment: str  # development, staging, production
    debug: bool

    # Server
    host: str
    port: int

    # Logging
    log_level: str

    # Feature flags
    feature_x_enabled: bool

    # Timeouts
    request_timeout: int
    connection_timeout: int

    # Optional fields with defaults
    max_workers: int = 4
    allowed_origins: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        """Validate configuration after initialization."""
        self._validate()
        self._log_config()

    def _validate(self) -> None:
        """Validate configuration values."""
        # Validate environment
        valid_environments = ("development", "staging", "production")
        if self.environment not in valid_environments:
            raise ConfigurationError(
                f"Invalid ENVIRONMENT: {self.environment}. "
                f"Must be one of: {valid_environments}"
            )

        # Validate log level
        valid_levels = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
        if self.log_level.upper() not in valid_levels:
            raise ConfigurationError(f"Invalid LOG_LEVEL: {self.log_level}")

        # Validate port
        if not 1 <= self.port <= 65535:
            raise ConfigurationError(f"Invalid PORT: {self.port}")

        # Validate timeouts
        if self.request_timeout < 1:
            raise ConfigurationError("REQUEST_TIMEOUT must be >= 1")

    def _log_config(self) -> None:
        """Log configuration (excluding sensitive values)."""
        logger.debug(
            "Configuration loaded",
            extra={
                "json_fields": {
                    "app_name": self.app_name,
                    "environment": self.environment,
                    "debug": self.debug,
                    "log_level": self.log_level,
                    "port": self.port,
                }
            },
        )

    @property
    def is_production(self) -> bool:
        """Check if running in production."""
        return self.environment == "production"

    @property
    def is_development(self) -> bool:
        """Check if running in development."""
        return self.environment == "development"


# Thread-safe singleton
_config: Config | None = None
_config_lock = threading.Lock()


def get_config() -> Config:
    """
    Get or create configuration singleton (thread-safe).

    Uses double-checked locking for efficiency.

    Returns:
        Config singleton instance
    """
    global _config

    # Fast path: already initialized
    if _config is not None:
        return _config

    # Slow path: acquire lock and create
    with _config_lock:
        # Double-check after lock
        if _config is not None:
            return _config

        _config = Config(
            # Application
            app_name=os.getenv("APP_NAME", "my-app"),
            environment=os.getenv("ENVIRONMENT", "development"),
            debug=_get_bool("DEBUG", False),

            # Server
            host=os.getenv("HOST", "0.0.0.0"),
            port=_get_int("PORT", 8080),

            # Logging
            log_level=os.getenv("LOG_LEVEL", "INFO"),

            # Feature flags
            feature_x_enabled=_get_bool("FEATURE_X_ENABLED", False),

            # Timeouts
            request_timeout=_get_int("REQUEST_TIMEOUT", 30),
            connection_timeout=_get_int("CONNECTION_TIMEOUT", 10),

            # Optional
            max_workers=_get_int("MAX_WORKERS", 4),
            allowed_origins=_get_list("ALLOWED_ORIGINS"),
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
print(f"App: {config.app_name}")
print(f"Environment: {config.environment}")
print(f"Debug: {config.debug}")

# Use properties
if config.is_production:
    setup_production_logging()
else:
    setup_development_logging()
```

### With Type Hints

```python
from config import get_config, Config

def start_server(config: Config) -> None:
    """Start server with configuration."""
    server = Server(
        host=config.host,
        port=config.port,
        timeout=config.request_timeout,
    )
    server.start()

# Get config and pass to functions
config = get_config()
start_server(config)
```

### Environment Variables

```bash
# .env or environment
export APP_NAME=my-service
export ENVIRONMENT=production
export DEBUG=false
export PORT=8080
export LOG_LEVEL=INFO
export REQUEST_TIMEOUT=30
export FEATURE_X_ENABLED=true
export ALLOWED_ORIGINS=https://example.com,https://api.example.com
```

## Adding New Configuration

### 1. Add Field to Dataclass

```python
@dataclass(frozen=True)
class Config:
    # ... existing fields ...

    # New field
    database_url: str
    database_pool_size: int
```

### 2. Add Validation

```python
def _validate(self) -> None:
    # ... existing validation ...

    # New validation
    if not self.database_url.startswith(("postgresql://", "mysql://")):
        raise ConfigurationError("DATABASE_URL must be a valid connection string")

    if self.database_pool_size < 1 or self.database_pool_size > 100:
        raise ConfigurationError("DATABASE_POOL_SIZE must be 1-100")
```

### 3. Load in get_config()

```python
_config = Config(
    # ... existing fields ...

    # New fields
    database_url=_require("DATABASE_URL"),  # Required
    database_pool_size=_get_int("DATABASE_POOL_SIZE", 10),  # Optional with default
)
```

## Testing

```python
import os
import pytest
from config import get_config, reset_config, ConfigurationError


@pytest.fixture(autouse=True)
def clean_config():
    """Reset config between tests."""
    reset_config()
    yield
    reset_config()


def test_default_values(monkeypatch):
    """Test default configuration values."""
    config = get_config()

    assert config.environment == "development"
    assert config.debug is False
    assert config.port == 8080


def test_environment_override(monkeypatch):
    """Test environment variable override."""
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("PORT", "3000")
    monkeypatch.setenv("DEBUG", "true")

    config = get_config()

    assert config.environment == "production"
    assert config.port == 3000
    assert config.debug is True


def test_invalid_environment(monkeypatch):
    """Test validation of invalid environment."""
    monkeypatch.setenv("ENVIRONMENT", "invalid")

    with pytest.raises(ConfigurationError):
        get_config()


def test_singleton():
    """Test that config is singleton."""
    config1 = get_config()
    config2 = get_config()

    assert config1 is config2


def test_thread_safety():
    """Test thread-safe initialization."""
    from concurrent.futures import ThreadPoolExecutor

    with ThreadPoolExecutor(max_workers=10) as executor:
        configs = list(executor.map(lambda _: get_config(), range(100)))

    # All should be the same instance
    assert all(c is configs[0] for c in configs)
```

## Best Practices

### Do's

- Use `frozen=True` for immutability
- Validate early in `__post_init__`
- Provide sensible defaults
- Use type hints
- Log config at startup (excluding secrets)

### Don'ts

- Don't store secrets in config (use secret managers)
- Don't modify config after creation
- Don't access `os.getenv()` directly in app code
- Don't create multiple Config instances

## Dependencies

```toml
# pyproject.toml - No additional dependencies!
# Uses only Python standard library
```

## References

- [Python Dataclasses](https://docs.python.org/3/library/dataclasses.html)
- [12 Factor App - Config](https://12factor.net/config)
- [Double-Checked Locking](https://en.wikipedia.org/wiki/Double-checked_locking)
