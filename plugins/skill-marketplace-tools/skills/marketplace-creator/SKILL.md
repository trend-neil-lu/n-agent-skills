---
name: marketplace-creator
description: Create a Claude Code plugin marketplace from scratch. Triggers on 'create marketplace', 'skill marketplace', 'plugin marketplace', 'setup marketplace', 'new marketplace'.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Skill Marketplace Creator

Create a complete Claude Code plugin marketplace with proper structure, validation scripts, and CI/CD automation.

## Marketplace Structure

```text
<marketplace-name>/
├── .claude-plugin/
│   ├── marketplace.json           # Central plugin registry
│   └── schemas/
│       └── marketplace.schema.json # JSON Schema for validation
├── .github/
│   └── workflows/
│       └── validate.yml           # CI validation workflow
├── plugins/
│   ├── _template/                 # Plugin template for new plugins
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   ├── skills/
│   │   │   └── example-skill/
│   │   │       └── SKILL.md
│   │   ├── commands/
│   │   │   └── hello.md
│   │   └── agents/
│   │       └── example-agent.md
│   └── <plugin-name>/             # Actual plugins
├── scripts/
│   ├── create-plugin.sh           # Create new plugin from template
│   ├── validate-plugin.sh         # Validate plugin structure
│   ├── register-plugin.sh         # Register plugin in marketplace
│   └── list-plugins.sh            # List all available plugins
├── .pre-commit-config.yaml        # Linting configuration
├── .markdownlint.jsonc            # Markdown linting rules
├── CLAUDE.md                      # Instructions for Claude Code
├── CONTRIBUTING.md                # Contribution guidelines
├── LICENSE
└── README.md
```

## Step 1: Create marketplace.json

```json
{
  "$schema": "./schemas/marketplace.schema.json",
  "name": "<marketplace-name>",
  "version": "1.0.0",
  "owner": {
    "name": "<your-name>",
    "email": "<your-email>"
  },
  "metadata": {
    "description": "A curated collection of Claude Code plugins",
    "homepage": "https://github.com/<org>/<repo>",
    "license": "MIT",
    "keywords": ["claude-code", "plugins", "skills"]
  },
  "categories": [
    {
      "id": "utilities",
      "name": "Utilities",
      "description": "General utility tools",
      "icon": "🔧"
    },
    {
      "id": "development",
      "name": "Development",
      "description": "Development workflow tools",
      "icon": "💻"
    }
  ],
  "plugins": []
}
```

## Step 2: Create JSON Schema

Create `.claude-plugin/schemas/marketplace.schema.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "marketplace.schema.json",
  "title": "Plugin Marketplace Schema",
  "type": "object",
  "required": ["name", "owner", "plugins"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9-]*$"
    },
    "version": {
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+$"
    },
    "owner": {
      "type": "object",
      "required": ["name"],
      "properties": {
        "name": { "type": "string" },
        "email": { "type": "string", "format": "email" }
      }
    },
    "plugins": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "source"],
        "properties": {
          "name": {
            "type": "string",
            "pattern": "^[a-z][a-z0-9-]*$"
          },
          "source": { "type": "string" },
          "version": {
            "type": "string",
            "pattern": "^\\d+\\.\\d+\\.\\d+$"
          },
          "category": { "type": "string" }
        }
      }
    }
  }
}
```

## Step 3: Create Validation Script

Create `scripts/validate-plugin.sh`:

```bash
#!/bin/bash
set -euo pipefail

PLUGIN_PATH="$1"
PLUGIN_NAME=$(basename "$PLUGIN_PATH")

echo "Validating plugin: $PLUGIN_NAME"

# Check required files
if [[ ! -f "$PLUGIN_PATH/.claude-plugin/plugin.json" ]]; then
    echo "✗ Missing .claude-plugin/plugin.json"
    exit 1
fi

# Validate plugin.json
if ! jq empty "$PLUGIN_PATH/.claude-plugin/plugin.json" 2>/dev/null; then
    echo "✗ Invalid JSON in plugin.json"
    exit 1
fi

# Check required fields
for field in name version description; do
    if ! jq -e ".$field" "$PLUGIN_PATH/.claude-plugin/plugin.json" >/dev/null 2>&1; then
        echo "✗ Missing required field: $field"
        exit 1
    fi
done

# Validate skills
if [[ -d "$PLUGIN_PATH/skills" ]]; then
    for skill_dir in "$PLUGIN_PATH/skills"/*/; do
        if [[ -d "$skill_dir" ]]; then
            skill_name=$(basename "$skill_dir")
            if [[ ! -f "$skill_dir/SKILL.md" ]]; then
                echo "✗ Skill $skill_name missing SKILL.md"
                exit 1
            fi
            # Check YAML front matter
            if ! head -1 "$skill_dir/SKILL.md" | grep -q "^---$"; then
                echo "✗ Skill $skill_name missing YAML front matter"
                exit 1
            fi
        fi
    done
fi

echo "✓ Plugin validation passed"
```

## Step 4: Create Plugin Template

Create `plugins/_template/.claude-plugin/plugin.json`:

```json
{
  "name": "{{PLUGIN_NAME}}",
  "version": "1.0.0",
  "description": "{{PLUGIN_DESCRIPTION}}",
  "author": {
    "name": "{{AUTHOR_NAME}}",
    "email": "{{AUTHOR_EMAIL}}"
  },
  "license": "MIT",
  "keywords": []
}
```

Create `plugins/_template/skills/example-skill/SKILL.md`:

```markdown
---
name: example-skill
description: Example skill description. Triggers on 'example', 'demo', 'test'.
allowed-tools: Read, Grep, Glob
---

# Example Skill

This is a template skill. Replace with your implementation.

## Usage

Describe how to use this skill.

## Output Format

Describe the expected output.
```

## Step 5: Create Plugin Script

Create `scripts/create-plugin.sh`:

```bash
#!/bin/bash
set -euo pipefail

PLUGIN_NAME="$1"
DESCRIPTION="${2:-A new Claude Code plugin}"
TEMPLATE_DIR="plugins/_template"
TARGET_DIR="plugins/$PLUGIN_NAME"

if [[ -d "$TARGET_DIR" ]]; then
    echo "Error: Plugin $PLUGIN_NAME already exists"
    exit 1
fi

cp -r "$TEMPLATE_DIR" "$TARGET_DIR"

# Replace placeholders
find "$TARGET_DIR" -type f -exec sed -i '' \
    -e "s/{{PLUGIN_NAME}}/$PLUGIN_NAME/g" \
    -e "s/{{PLUGIN_DESCRIPTION}}/$DESCRIPTION/g" \
    {} \;

echo "Created plugin: $TARGET_DIR"
echo "Next steps:"
echo "  1. Edit $TARGET_DIR/.claude-plugin/plugin.json"
echo "  2. Add skills in $TARGET_DIR/skills/"
echo "  3. Run ./scripts/validate-plugin.sh $PLUGIN_NAME"
```

## Step 6: Create CLAUDE.md

```markdown
# CLAUDE.md

## Project Overview

A Claude Code plugin marketplace with curated plugins and skills.

## Common Commands

```bash
# Create a new plugin
./scripts/create-plugin.sh <name> ["description"]

# Validate a plugin
./scripts/validate-plugin.sh <plugin-name>

# Test locally
claude --plugin-dir ./plugins/<plugin-name>
```

## Plugin Structure

- `.claude-plugin/plugin.json` - Required manifest
- `skills/*/SKILL.md` - Skills with YAML front matter
- `commands/*.md` - Slash commands
- `agents/*.md` - Specialized agents

## Naming Conventions

- Plugin names: kebab-case (`my-plugin`)
- Version: semver (`1.0.0`)
- Skills: Include trigger keywords in description

## Checklist

When creating a marketplace:

- [ ] Create `.claude-plugin/marketplace.json` with owner info
- [ ] Add JSON schema for validation
- [ ] Create `_template` plugin for new plugins
- [ ] Add validation script with proper checks
- [ ] Add create-plugin script for bootstrapping
- [ ] Set up pre-commit hooks for linting
- [ ] Create CLAUDE.md with project instructions
- [ ] Add CONTRIBUTING.md with guidelines
- [ ] Add GitHub Actions for CI validation
- [ ] Create at least one example plugin
