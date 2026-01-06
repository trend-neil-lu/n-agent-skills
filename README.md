# Agent Skills - Claude Code Plugin Marketplace

A curated collection of Claude Code plugins and skills for enhanced AI-assisted development.

## Quick Start

### Using Plugins from this Marketplace

```bash
# Add this marketplace to Claude Code
claude marketplace add https://github.com/trend-neil-lu/n-agent-skills

# Install a plugin
claude plugin install n-agent-skills/example-skills

# List available plugins
claude plugin list --marketplace n-agent-skills
```

### Local Development

```bash
# Clone the repository
git clone https://github.com/trend-neil-lu/n-agent-skills.git
cd n-agent-skills

# Test a plugin locally
claude --plugin-dir ./plugins/example-skills
```

## Available Plugins

| Plugin | Description | Category | Status |
|--------|-------------|----------|--------|
| [example-skills](./plugins/example-skills) | Code review, documentation, and security scanning | Utilities | Stable |
| [gcp-cloudrun](./plugins/gcp-cloudrun) | GCP Cloud Run Python services/jobs with OpenTelemetry | DevOps | Stable |
| [python-gcp](./plugins/python-gcp) | Python patterns for GCP: Cloud Logging, Pub/Sub, Cloud Trace | DevOps | Stable |
| [python-best-practices](./plugins/python-best-practices) | Pure Python patterns: logging, config, error handling | Development | Stable |
| [skill-marketplace-tools](./plugins/skill-marketplace-tools) | Tools for creating Claude Code plugin marketplaces | Utilities | Stable |

## Creating a New Plugin

### Using the Template

```bash
# Create a new plugin from template
./scripts/create-plugin.sh my-new-plugin "My plugin description"

# Or manually copy the template
cp -r plugins/_template plugins/my-new-plugin
```

### Plugin Structure

```text
my-plugin/
├── .claude-plugin/
│   └── plugin.json      # Required: Plugin manifest
├── skills/              # AI skills with SKILL.md files
│   └── my-skill/
│       └── SKILL.md
├── commands/            # Slash commands (.md files)
├── agents/              # Specialized agents (.md files)
├── hooks/               # Event hooks (hooks.json)
├── scripts/             # Helper scripts
└── README.md            # Plugin documentation
```

### Required Files

**`.claude-plugin/plugin.json`**

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

**`skills/my-skill/SKILL.md`**

```markdown
---
name: my-skill
description: What this skill does. Include trigger keywords here.
allowed-tools: Read, Grep, Glob
---

# My Skill

Instructions for Claude on how to use this skill.
```

## Categories

| Category | Description | Icon |
|----------|-------------|------|
| Utilities | General utility tools | 🔧 |
| Development | Dev workflow tools | 💻 |
| Documentation | Doc generation | 📚 |
| Security | Security analysis | 🛡️ |
| Testing | Testing and QA | ✅ |
| DevOps | CI/CD and infrastructure | 🚀 |

## CLI Scripts

| Script | Description |
|--------|-------------|
| `scripts/create-plugin.sh` | Create new plugin from template |
| `scripts/validate-plugin.sh` | Validate plugin structure |
| `scripts/register-plugin.sh` | Register plugin in marketplace |

## Best Practices

### Skills

- Keep `SKILL.md` under 500 lines
- Include trigger keywords in description
- Use `allowed-tools` to limit capabilities
- Reference additional files for complex instructions

### Commands

- Use descriptive names matching their function
- Include `$ARGUMENTS` placeholder for parameters
- Provide clear usage instructions

### Hooks

- Use `${CLAUDE_PLUGIN_ROOT}` for paths
- Make scripts executable (`chmod +x`)
- Handle errors gracefully

## Contributing

1. Fork this repository
2. Create a new plugin using the template
3. Test locally with `claude --plugin-dir`
4. Submit a pull request

### Submission Checklist

- [ ] Plugin follows the standard structure
- [ ] `plugin.json` has all required fields
- [ ] Skills have proper `SKILL.md` files
- [ ] README.md documents all features
- [ ] Validated with `scripts/validate-plugin.sh`

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- [Documentation](https://code.claude.com/docs)
- [Issues](https://github.com/trend-neil-lu/n-agent-skills/issues)
- [Discussions](https://github.com/trend-neil-lu/n-agent-skills/discussions)
