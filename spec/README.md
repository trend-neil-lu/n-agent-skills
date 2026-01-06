# Agent Skills Specification

This directory contains documentation about the Agent Skills specification used by Claude Code plugins.

## Official Specification

For the complete and authoritative Agent Skills specification, see:

- [Anthropic Skills Repository](https://github.com/anthropics/skills)
- [Agent Skills Specification](https://agentskills.io/specification)

## Quick Reference

### SKILL.md Format

Skills are defined using a `SKILL.md` file with YAML frontmatter:

```markdown
---
name: skill-name
description: A clear description of what this skill does and when to use it.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Skill Title

Instructions for Claude on how to use this skill.

## Guidelines

- Guideline 1
- Guideline 2

## Examples

- Example usage 1
- Example usage 2
```

### Required Fields

| Field | Description |
|-------|-------------|
| `name` | Unique skill identifier (lowercase, hyphen-separated) |
| `description` | Comprehensive explanation of skill's purpose and trigger keywords |

### Optional Fields

| Field | Description |
|-------|-------------|
| `allowed-tools` | Comma-separated list of tools the skill can use |
| `version` | Skill version (semver format) |

### Trigger Keywords

Skills are activated based on keywords in the `description` field. Include phrases like:

- "Use this skill when..."
- "Triggers on 'keyword1', 'keyword2', 'keyword3'"
- "Activate for tasks involving..."

### Best Practices

1. **Clear Purpose**: Each skill should do one thing well
2. **Trigger Keywords**: Include 3-5 specific trigger phrases in description
3. **Minimal Tools**: Only request tools that are actually needed
4. **Concrete Examples**: Provide examples of input/output
5. **Structured Output**: Define output format for consistency
6. **Size Limit**: Keep SKILL.md under 500 lines; reference external files for complex instructions

## Plugin Structure

```text
plugin-name/
├── .claude-plugin/
│   └── plugin.json      # Plugin manifest
├── skills/
│   └── skill-name/
│       └── SKILL.md     # Skill definition
├── commands/            # Slash commands
├── agents/              # Specialized agents
└── hooks/               # Event hooks
```

## Token Efficiency

- Skills use ~100 tokens during metadata scanning
- When activated, full skill content loads at <5k tokens
- Bundled resources only load as needed

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)
- [SkillsMP Community](https://skillsmp.com/)
