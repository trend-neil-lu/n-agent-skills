---
name: gcp-cloudrun-python
description: Create and manage GCP Cloud Run services/jobs with Python best practices. Triggers on 'create cloud run', 'gcp cloud run', 'new cloud run service', 'cloud run job', 'cloudrun python'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# GCP Cloud Run Python Service/Job Skill

Create production-ready GCP Cloud Run services and jobs using Python best practices (2025).

> **Note**: This skill is for **Python only**. For other languages, refer to official Cloud Run documentation.

## Project Structure

```text
<project-name>/
├── .github/
│   └── workflows/           # CI/CD pipelines
│       ├── build.yml
│       ├── release.yml
│       └── test-and-publish-for-pr.yml
├── .pre-commit-config.yaml  # Pre-commit hooks (ruff, pytest)
├── <module_name>/           # Main Python module (snake_case)
│   ├── __init__.py
│   ├── main.py              # Entry point with main function
│   ├── config.py            # Configuration management
│   ├── logging.py           # Structured JSON logging
│   └── ...
├── tests/
│   ├── conftest.py
│   └── test_*.py
├── Dockerfile               # Multi-stage build
├── Makefile                 # Development commands
├── pyproject.toml           # Project config (uv, ruff, pytest)
├── uv.lock                  # Dependency lock file
├── version.json             # Version management
└── README.md
```

## Technology Stack

| Component | Tool | Notes |
|-----------|------|-------|
| Python | 3.13+ | Latest stable |
| Package Manager | uv | Fast, reliable |
| Linter | ruff | Replaces flake8, isort, black |
| Type Checker | pyright | Strict mode |
| Testing | pytest | With coverage |
| Pre-commit | ruff + pytest | Run before commit |
| Container | podman/docker | Multi-stage build |
| Base Image | python:3.13-slim | Minimal size |

## Key Configuration Files

### pyproject.toml

```toml
[project]
name = "<project-name>"
dynamic = ["version"]
requires-python = ">=3.13"
dependencies = [
    "functions-framework>=3.8.1",
    "google-cloud-storage>=2.18.2",
    "google-cloud-pubsub>=2.23.1",
    "cloudevents>=1.10.1",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.3",
    "pytest-cov>=6.0.0",
    "ruff>=0.7.0",
    "pyright>=1.1.389",
    "pre-commit>=4.0.0",
]

[tool.uv]
managed = true
package = true

[tool.ruff]
line-length = 100
target-version = "py313"

[tool.ruff.lint]
select = ["E", "F", "I", "N", "W", "UP", "B", "C4", "SIM"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = ["--cov=<module>", "--cov-report=xml", "-v"]

[tool.coverage.report]
fail_under = 80

[tool.hatch.version]
path = "version.json"
pattern = '"version":\s*"(?P<version>[^"]+)"'
```

### Makefile (Standard Targets)

```makefile
PYTHON := uv run python
UV := uv
PROJECT_NAME := <project-name>

.PHONY: setup
setup: ## Set up development environment
	$(UV) sync --all-extras
	$(UV) run pre-commit install

.PHONY: lint
lint: ## Run ruff and pyright
	$(UV) run ruff check src/ tests/
	$(UV) run pyright src/

.PHONY: format
format: ## Format code
	$(UV) run ruff format src/ tests/
	$(UV) run ruff check --fix src/ tests/

.PHONY: test
test: ## Run unit tests
	$(UV) run pytest -m "not integration" --cov-report=term-missing

.PHONY: build-docker
build-docker: ## Build Docker image
	podman build -t $(PROJECT_NAME):latest .

.PHONY: run-local
run-local: ## Run locally with functions-framework
	$(UV) run functions-framework --target=main --debug --port=8080

.PHONY: clean
clean: ## Clean build artifacts
	rm -rf .venv .pytest_cache .coverage coverage.xml
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
```

### Dockerfile (Multi-stage)

```dockerfile
# Stage 1: Builder
FROM python:3.13-slim AS builder
WORKDIR /build
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
COPY <module>/ ./<module>/
COPY version.json ./

# Stage 2: Runtime
FROM python:3.13-slim
WORKDIR /app
COPY --from=builder /build/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
COPY <module>/ /app/<module>/
COPY version.json /app/
ENV PYTHONUNBUFFERED=1 PORT=8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health').read()"
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
CMD ["/app/.venv/bin/python", "-m", "functions_framework", "--target=main", "--port=8080"]
```

### .pre-commit-config.yaml

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.1
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: local
    hooks:
      - id: pytest
        name: Run pytest
        entry: uv run pytest -m "not integration" -q
        language: system
        pass_filenames: false
        always_run: true

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-toml
```

### version.json

```json
{
  "version": "1.0.0"
}
```

## Cloud Run Best Practices

### Performance

- Enable startup CPU boost (`--cpu-boost`)
- Use `functions-framework` for HTTP handling
- Minimal base image (`python:3.13-slim`)
- Multi-stage Docker build
- Set appropriate concurrency (default: 80)

### Security

- Non-root user in container
- No hardcoded secrets (use Secret Manager)
- Minimal attack surface
- Health check endpoints

### Observability

- Structured JSON logging for Cloud Logging
- OpenTelemetry for distributed tracing with Cloud Trace
- Health check endpoint (`/health`)

## OpenTelemetry Integration

### Dependencies

```toml
# Add to pyproject.toml dependencies
dependencies = [
    # ... existing deps ...
    # OpenTelemetry
    "opentelemetry-api>=1.27.0",
    "opentelemetry-sdk>=1.27.0",
    "opentelemetry-exporter-gcp-trace>=1.7.0",
    "opentelemetry-exporter-gcp-monitoring>=1.7.0",
    "opentelemetry-instrumentation-flask>=0.48b0",
    "opentelemetry-instrumentation-requests>=0.48b0",
    "opentelemetry-propagator-gcp>=1.7.0",
    "opentelemetry-resourcedetector-gcp>=1.7.0",
]
```

### Tracing Setup (observability.py)

```python
"""OpenTelemetry tracing for Cloud Run with Cloud Trace export."""

import os
from typing import Any

from opentelemetry import trace
from opentelemetry.exporter.cloud_trace import CloudTraceSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.cloud_trace_propagator import CloudTraceFormatPropagator
from opentelemetry.resourcedetector.gcp_resource_detector import GoogleCloudResourceDetector
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased

_tracer = None
_tracing_enabled = False


def setup_tracing(
    service_name: str,
    project_id: str | None = None,
    sampling_ratio: float = 0.05,
) -> None:
    """
    Setup OpenTelemetry tracing with Cloud Trace exporter.

    Args:
        service_name: Service name for trace identification
        project_id: GCP project ID (auto-detected if None)
        sampling_ratio: Trace sampling ratio (default 5%)
    """
    global _tracer, _tracing_enabled

    # Only enable in Cloud Run (K_SERVICE env var present)
    if not os.environ.get("K_SERVICE"):
        return

    try:
        # Merge GCP-detected resource with service info
        gcp_resource = GoogleCloudResourceDetector().detect()
        base_resource = Resource.create({
            "service.name": service_name,
            "service.version": os.environ.get("K_REVISION", "unknown"),
        })
        resource = gcp_resource.merge(base_resource)

        # Cloud Trace exporter
        exporter = CloudTraceSpanExporter(
            project_id=project_id,
            resource_regex=r"(service|cloud|faas)\..*",
        )

        # Sampler: respect parent decisions, sample root spans at ratio
        sampler = ParentBased(root=TraceIdRatioBased(sampling_ratio))

        # Setup provider
        provider = TracerProvider(resource=resource, sampler=sampler)
        provider.add_span_processor(BatchSpanProcessor(exporter))
        trace.set_tracer_provider(provider)

        # Use Cloud Trace propagator for X-Cloud-Trace-Context header
        set_global_textmap(CloudTraceFormatPropagator())

        _tracer = trace.get_tracer(__name__)
        _tracing_enabled = True

    except Exception:
        _tracing_enabled = False


def get_tracer() -> trace.Tracer | None:
    """Get the configured tracer, or None if disabled."""
    return _tracer if _tracing_enabled else None


def instrument_flask_app(app: Any) -> None:
    """Instrument Flask app for automatic request tracing."""
    if _tracing_enabled:
        FlaskInstrumentor().instrument_app(
            app,
            excluded_urls=r"health,startup,liveness,readiness",
        )


def instrument_requests() -> None:
    """Instrument requests library for outgoing HTTP tracing."""
    if _tracing_enabled:
        RequestsInstrumentor().instrument(
            excluded_urls="metadata.google.internal",
        )


def create_span(name: str, attributes: dict[str, Any] | None = None):
    """Create a new span context manager."""
    from contextlib import nullcontext

    tracer = get_tracer()
    if tracer:
        return tracer.start_as_current_span(name, attributes=attributes or {})
    return nullcontext()
```

### Usage in main.py

```python
from flask import Flask
from observability import (
    setup_tracing,
    instrument_flask_app,
    instrument_requests,
    create_span,
)

app = Flask(__name__)

# Initialize tracing on startup
setup_tracing(service_name="my-service")
instrument_flask_app(app)
instrument_requests()


@app.route("/process")
def process():
    with create_span("process_data", {"data.size": 100}):
        # Your business logic here
        result = do_work()
    return result
```

### Key Points

1. **Auto-detection**: Uses `GoogleCloudResourceDetector` for Cloud Run metadata
2. **Sampling**: Default 5% to control costs; adjust via `sampling_ratio`
3. **Propagation**: Uses `X-Cloud-Trace-Context` header for distributed tracing
4. **Exclusions**: Health endpoints excluded to reduce noise
5. **Graceful fallback**: No-op when not in Cloud Run environment

### Endpoints Pattern

```python
# main.py
import functions_framework
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

@functions_framework.http
def main(request):
    """Main entry point for Cloud Run."""
    # Handle Pub/Sub push or HTTP requests
    return "OK", 200
```

## Usage

### Create New Project

```bash
# Initialize with uv
uv init <project-name>
cd <project-name>

# Add dependencies
uv add functions-framework google-cloud-storage google-cloud-pubsub
uv add --dev pytest pytest-cov ruff pyright pre-commit
```

### Development Workflow

```bash
make setup      # First time setup
make lint       # Check code quality
make format     # Auto-format code
make test       # Run tests
make build-docker  # Build container
make run-local  # Test locally
```

### Deploy to Cloud Run

```bash
gcloud run deploy <service-name> \
  --source . \
  --region asia-east1 \
  --cpu-boost \
  --memory 512Mi \
  --max-instances 100 \
  --no-allow-unauthenticated
```

## References

- [Cloud Run Best Practices](https://cloud.google.com/run/docs/tips/general)
- [Cloud Run Python Tips](https://cloud.google.com/run/docs/tips/python)
- [uv Documentation](https://docs.astral.sh/uv/)
- [ruff Documentation](https://docs.astral.sh/ruff/)
