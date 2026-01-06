---
name: python-version-json
description: Unified version management for Python projects using version.json as single source of truth. Triggers on 'version.json', 'python version', 'unified versioning', 'hatch version'.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Python Unified Version Management with version.json

Use `version.json` as the single source of truth for Python project versioning, integrated with pyproject.toml (hatch), runtime code, Docker, and CI/CD.

## Overview

```text
version.json          ← Single source of truth
    ↓
┌───┴───┐
│       │
▼       ▼
pyproject.toml    __init__.py
(build time)      (runtime)
    ↓                 ↓
  wheel/sdist     from pkg import __version__
    ↓
Dockerfile → Container image
    ↓
GitHub Actions → Git tag, deployment
```

## Files Structure

```text
project/
├── version.json              # Single source of truth
├── pyproject.toml            # Build-time version (hatch)
├── <module>/__init__.py      # Runtime version loading
├── Dockerfile                # Copy version.json to container
└── .github/workflows/*.yml   # CI/CD version reading
```

## version.json

```json
{
    "version": "1.0.0"
}
```

**Extended format** (for dependency tracking):

```json
{
    "version": "1.0.0",
    "dependencies": {
        "lib-avscan": "2.1.0",
        "lib-common": "latest"
    }
}
```

## pyproject.toml Configuration

### Using Hatch (Recommended)

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "my-project"
dynamic = ["version"]  # Version is dynamic, read from version.json
description = "My project description"
requires-python = ">=3.13"

[tool.hatch.version]
path = "version.json"
pattern = '"version":\s*"(?P<version>[^"]+)"'

[tool.hatch.build.targets.wheel]
packages = ["my_module"]
```

### Key Points

| Config | Purpose |
|--------|---------|
| `dynamic = ["version"]` | Tells PEP 621 that version is dynamically determined |
| `[tool.hatch.version]` | Hatch reads version from specified file |
| `path = "version.json"` | Path to version file |
| `pattern = '...'` | Regex to extract version string |

## Runtime Version Loading

### \_\_init\_\_.py

```python
"""
My Module.

Copyright (C) 2025 My Company. All rights reserved.
"""

import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)


def _get_version() -> str:
    """
    Get version from version.json file.

    Returns:
        Version string, defaults to "unknown" if file not found
    """
    try:
        # version.json is at project root (parent of module directory)
        version_file = Path(__file__).parent.parent / "version.json"
        if version_file.exists():
            with open(version_file) as f:
                version_data = json.load(f)
                return version_data.get("version", "unknown")
    except Exception as e:
        logger.warning(f"Failed to read version.json: {e}")
    return "unknown"


__version__ = _get_version()
```

### Usage in Code

```python
from my_module import __version__

print(f"Running version {__version__}")

# In logging setup
logging.info("Service started", extra={"version": __version__})

# In API response
@app.route("/health")
def health():
    return {"status": "healthy", "version": __version__}
```

### Alternative: Using importlib.metadata

For installed packages, you can also use:

```python
from importlib.metadata import version

__version__ = version("my-package")
```

However, `version.json` approach is preferred because:

- Works in development without installation
- Works in Docker containers
- Single source of truth for all contexts

## Dockerfile Integration

```dockerfile
# Stage 1: Builder
FROM python:3.13-slim AS builder
WORKDIR /build
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
COPY my_module/ ./my_module/
COPY version.json ./              # Include version.json

# Stage 2: Runtime
FROM python:3.13-slim
WORKDIR /app
COPY --from=builder /build/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
COPY my_module/ /app/my_module/
COPY version.json /app/           # Copy to runtime
CMD ["python", "-m", "my_module"]
```

## GitHub Actions Integration

### Read Version

```yaml
- name: Get version
  id: version
  run: echo "version=$(jq -r .version version.json)" >> "$GITHUB_OUTPUT"

- name: Use version
  run: echo "Deploying version ${{ steps.version.outputs.version }}"
```

### Check if Version Already Published

```yaml
- name: Check if version exists
  id: check
  env:
    VERSION: ${{ steps.version.outputs.version }}
  run: |
    if git ls-remote --tags origin | grep -q "refs/tags/${VERSION}$"; then
      echo "exists=true" >> "$GITHUB_OUTPUT"
    else
      echo "exists=false" >> "$GITHUB_OUTPUT"
    fi

- name: Skip if already published
  if: steps.check.outputs.exists == 'true'
  run: echo "Version ${VERSION} already published, skipping"
```

### Create Git Tag After Deployment

```yaml
- name: Create Git tag
  if: steps.check.outputs.exists == 'false'
  uses: actions/github-script@v7
  with:
    script: |
      const version = '${{ steps.version.outputs.version }}';
      try {
        await github.rest.git.getRef({
          owner: context.repo.owner,
          repo: context.repo.repo,
          ref: `tags/${version}`
        });
        console.log(`Tag ${version} already exists`);
      } catch (error) {
        if (error.status === 404) {
          await github.rest.git.createRef({
            owner: context.repo.owner,
            repo: context.repo.repo,
            ref: `refs/tags/${version}`,
            sha: context.sha
          });
          console.log(`Created tag ${version}`);
        }
      }
```

### Docker Image Tagging

```yaml
- name: Tag Docker image with version
  env:
    VERSION: ${{ steps.version.outputs.version }}
    REGISTRY: asia-docker.pkg.dev/my-project/my-repo
  run: |
    docker tag my-image:latest ${REGISTRY}/my-image:${VERSION}
    docker tag my-image:latest ${REGISTRY}/my-image:latest
    docker push ${REGISTRY}/my-image:${VERSION}
    docker push ${REGISTRY}/my-image:latest
```

## Version Bump Workflow

### Manual Bump Script

```bash
#!/bin/bash
# scripts/bump-version.sh

CURRENT=$(jq -r .version version.json)
echo "Current version: ${CURRENT}"

# Parse version
IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT}"

case "${1:-patch}" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"
echo "New version: ${NEW}"

# Update version.json
jq --arg v "${NEW}" '.version = $v' version.json > tmp.json && mv tmp.json version.json

echo "Updated version.json to ${NEW}"
```

### GitHub Actions Version Bump

```yaml
# .github/workflows/bump-version.yml
name: Bump Version

on:
  workflow_dispatch:
    inputs:
      bump_type:
        description: 'Version bump type'
        required: true
        default: 'patch'
        type: choice
        options:
          - patch
          - minor
          - major

jobs:
  bump:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Bump version
        id: bump
        run: |
          CURRENT=$(jq -r .version version.json)
          IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT}"

          case "${{ inputs.bump_type }}" in
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            patch) PATCH=$((PATCH + 1)) ;;
          esac

          NEW="${MAJOR}.${MINOR}.${PATCH}"
          jq --arg v "${NEW}" '.version = $v' version.json > tmp.json
          mv tmp.json version.json

          echo "old_version=${CURRENT}" >> "$GITHUB_OUTPUT"
          echo "new_version=${NEW}" >> "$GITHUB_OUTPUT"

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add version.json
          git commit -m "Bump version to ${{ steps.bump.outputs.new_version }}"
          git push
```

## Best Practices

### Version Format

- Use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`
- Examples: `1.0.0`, `2.1.3`, `0.9.0`

### Git Tag Workflow

1. Develop on feature branches
2. Merge to `main` triggers CI
3. CI reads `version.json`
4. If version not tagged, deploy and create tag
5. If version already tagged, skip deployment

### When to Bump Version

| Change Type | Bump | Example |
|-------------|------|---------|
| Breaking API changes | Major | `1.0.0` → `2.0.0` |
| New features (backward compatible) | Minor | `1.0.0` → `1.1.0` |
| Bug fixes, patches | Patch | `1.0.0` → `1.0.1` |

### Don't Forget

- [ ] Include `version.json` in Docker build
- [ ] Include `version.json` in wheel package (via `pyproject.toml`)
- [ ] Add version to health check endpoints
- [ ] Log version on service startup
- [ ] Tag Docker images with version

## References

- [Hatch Version Source](https://hatch.pypa.io/latest/version/)
- [PEP 621 - Project Metadata](https://peps.python.org/pep-0621/)
- [Semantic Versioning](https://semver.org/)
