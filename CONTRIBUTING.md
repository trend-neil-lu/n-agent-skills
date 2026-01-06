# Contributing to Agent Skills

Thank you for your interest in contributing to the Claude Code Plugin Marketplace!

## Getting Started

### Prerequisites

- Git
- Bash
- jq (for JSON processing)
- pre-commit (for linting)

### Setup

```bash
# Clone the repository
git clone https://github.com/trend-neil-lu/n-agent-skills.git
cd n-agent-skills

# Install pre-commit hooks
pre-commit install
```

## Creating a New Plugin

### Quick Start

```bash
# Create a new plugin from template
./scripts/create-plugin.sh my-plugin "My awesome plugin description"

# Validate the plugin
./scripts/validate-plugin.sh my-plugin

# Test locally
claude --plugin-dir ./plugins/my-plugin
```

### Plugin Structure

```text
plugins/my-plugin/
├── .claude-plugin/
│   └── plugin.json      # Required: Plugin manifest
├── skills/              # AI skills (SKILL.md files)
│   └── my-skill/
│       └── SKILL.md
├── commands/            # Slash commands (.md files)
├── agents/              # Specialized agents (.md files)
├── hooks/               # Event hooks (hooks.json)
└── scripts/             # Helper scripts
```

### Required Files

#### plugin.json

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What my plugin does",
  "author": {
    "name": "Your Name"
  },
  "license": "MIT",
  "keywords": ["keyword1", "keyword2"]
}
```

#### SKILL.md Format

```markdown
---
name: my-skill
description: |
  Brief description of what this skill does.
  Triggers on 'keyword1', 'keyword2', 'keyword3'.
allowed-tools: Read, Grep, Glob
---

# My Skill Title

Detailed instructions for Claude on how to use this skill.
```

## Writing Good Skills

### Best Practices

1. **Clear Trigger Keywords**: Include 3-5 trigger keywords at the end of the description
2. **Minimal Tools**: Only request tools that are actually needed
3. **Concrete Examples**: Provide examples of input/output
4. **Structured Output**: Define output format for consistency
5. **Keep It Focused**: One skill should do one thing well

### Example

```markdown
---
name: api-designer
description: |
  Design RESTful APIs with OpenAPI 3.0 specification.
  Triggers on 'design api', 'create api spec', 'openapi design'.
allowed-tools: Read, Write, Edit
---

# API Designer

Design RESTful APIs following best practices.

## Input

- Describe the resource and operations needed
- Specify authentication requirements
- List any constraints or business rules

## Output

OpenAPI 3.0 specification in YAML format.
```

## Submitting Your Plugin

### Pre-submission Checklist

- [ ] Plugin follows the standard structure
- [ ] `plugin.json` has all required fields (name, version, description)
- [ ] Version follows semver format (x.y.z)
- [ ] Each skill has a valid `SKILL.md` with YAML front matter
- [ ] Skill descriptions include trigger keywords
- [ ] Validated with `./scripts/validate-plugin.sh`
- [ ] Pre-commit hooks pass (`pre-commit run --all-files`)
- [ ] Tested locally with Claude Code

### Pull Request Process

1. **Fork** this repository
2. **Create a branch**: `git checkout -b add-my-plugin`
3. **Create your plugin**: `./scripts/create-plugin.sh my-plugin`
4. **Develop and test** your skills
5. **Register in marketplace**: `./scripts/register-plugin.sh my-plugin`
6. **Commit changes**: Write clear commit messages
7. **Push and create PR**: Include description of what your plugin does

### PR Template

```markdown
## Description

Brief description of what this plugin provides.

## Skills Included

- `skill-name`: What it does

## Testing Done

- [ ] Tested locally with claude --plugin-dir
- [ ] Validated with validate-plugin.sh
- [ ] Pre-commit hooks pass

## Screenshots/Examples

(Optional) Show examples of the plugin in action.
```

## Code Style

### Shell Scripts

- Use `shellcheck` for linting
- Follow Google Shell Style Guide
- Use `set -euo pipefail` at the start

### Markdown

- Use `markdownlint` for linting
- Keep lines readable (no hard limit, but reasonable)
- Use ATX-style headers (`#` not underlines)

### JSON

- Use 2-space indentation
- Keep arrays on single line if short
- Validate with `jq`

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions or ideas

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
