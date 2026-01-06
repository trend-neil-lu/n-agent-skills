---
description: Triggers a comprehensive code review on specified files or the current working directory
---

# Code Review Command

Perform a thorough code review on the specified files or directory.

## Target

If arguments are provided ("$ARGUMENTS"), review those specific files or directories.
Otherwise, review staged changes in git or the current working directory.

## Review Process

1. **Identify files to review** - Parse arguments or detect changed files
2. **Analyze code** - Check for issues, patterns, and best practices
3. **Generate report** - Provide structured feedback with actionable items

## Output

Provide a structured review report with:

- Critical issues requiring immediate attention
- Warnings about potential problems
- Suggestions for improvement
- Positive observations about good patterns
