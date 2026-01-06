---
description: Runs a security scan on the codebase to detect vulnerabilities and secrets
---

# Security Check Command

Perform a security scan on the specified files or the entire codebase.

## Target

If arguments are provided ("$ARGUMENTS"), scan those specific files or directories.
Otherwise, scan the entire repository for security issues.

## Scan Process

1. **Secrets detection** - Look for exposed credentials, API keys, tokens
2. **Vulnerability scan** - Check for common security vulnerabilities
3. **Configuration review** - Identify insecure configurations
4. **Generate report** - Provide severity-ranked findings with remediation steps

## Output

Provide a security report with findings categorized by severity:

- 🔴 Critical - Immediate action required
- 🟠 High - Should be fixed soon
- 🟡 Medium - Address when possible
- 🔵 Low - Informational findings
