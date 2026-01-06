# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Claude Code plugin marketplace - a curated collection of plugins and skills for enhanced AI-assisted development. Plugins are self-contained packages with skills, commands, agents, and hooks.

## Git Commit Guidelines

- **ALWAYS ask user to review changes before committing** - never auto-commit
- Do NOT include Claude attribution in commits (no "Generated with Claude Code" or "Co-Authored-By: Claude")
- Write clean commit messages focusing on the changes made

## Linting

```bash
# Install pre-commit hooks (first time setup)
pre-commit install

# Run all linters manually
pre-commit run --all-files

# Run on staged files only
pre-commit run
```

Linters configured: markdownlint, shellcheck, JSON validation, trailing whitespace, end-of-file fixer.

## Common Commands

```bash
# Create a new plugin from template
./scripts/create-plugin.sh <plugin-name> ["description"]

# Validate a plugin's structure
./scripts/validate-plugin.sh <plugin-name|plugin-path>

# Register a plugin in the marketplace
./scripts/register-plugin.sh <plugin-name>

# List all available plugins
./scripts/list-plugins.sh

# Test a plugin locally
claude --plugin-dir ./plugins/<plugin-name>
```

## Architecture

### Plugin Structure

```text
plugins/<plugin-name>/
├── .claude-plugin/
│   └── plugin.json      # Required: Plugin manifest (name, version, description, author)
├── skills/              # AI skills with SKILL.md files
│   └── <skill-name>/
│       └── SKILL.md     # Contains YAML front matter (name, description, allowed-tools)
├── commands/            # Slash commands (markdown files)
├── agents/              # Specialized agents (markdown files)
├── hooks/               # Event hooks (hooks.json)
│   └── hooks.json       # PostToolUse, PreToolUse event handlers
└── scripts/             # Helper scripts (use ${CLAUDE_PLUGIN_ROOT})
```

### Marketplace Registry

- `.claude-plugin/marketplace.json` - Central registry of all plugins with categories
- `.claude-plugin/schemas/marketplace.schema.json` - JSON Schema for validation
- Plugins reference via `"source": "./plugins/<plugin-name>"`

### Key Conventions

- Plugin names must be kebab-case: `^[a-z][a-z0-9-]*$`
- Version must be semver: `^\d+\.\d+\.\d+$`
- Skills trigger on keywords defined in `description` field of SKILL.md
- Hooks use `${CLAUDE_PLUGIN_ROOT}` for portable paths

## SKILL.md Format

```markdown
---
name: skill-name
description: Skill description with trigger keywords for activation
allowed-tools: Read, Grep, Glob, Bash
---

# Skill Title

Instructions for Claude on how to use this skill.
```

## Validation Requirements

A valid plugin must have:

1. `.claude-plugin/plugin.json` with `name`, `version`, `description` fields
2. Each skill directory must contain a `SKILL.md` with YAML front matter
3. Commands require `description` in front matter
