---
name: security-scanner
description: Scans code for security vulnerabilities, secrets, and common security anti-patterns. Use when checking security, finding vulnerabilities, or auditing code safety. Triggers on 'security scan', 'find vulnerabilities', 'check security', 'audit security', or 'find secrets'.
allowed-tools: Read, Grep, Glob, Bash
---

# Security Scanner Skill

Identifies security vulnerabilities and recommends fixes.

## Scan Categories

### 1. Secrets Detection

- API keys and tokens
- Database credentials
- Private keys
- Password strings
- AWS/GCP/Azure credentials

### 2. OWASP Top 10

- A01: Broken Access Control
- A02: Cryptographic Failures
- A03: Injection
- A04: Insecure Design
- A05: Security Misconfiguration
- A06: Vulnerable Components
- A07: Authentication Failures
- A08: Data Integrity Failures
- A09: Logging Failures
- A10: SSRF

### 3. Common Vulnerabilities

- SQL Injection
- XSS (Cross-Site Scripting)
- CSRF (Cross-Site Request Forgery)
- Path Traversal
- Command Injection
- Insecure Deserialization

### 4. Configuration Issues

- Debug mode in production
- Weak encryption settings
- Missing security headers
- Overly permissive CORS
- Insecure cookie settings

## Detection Patterns

### Secret Patterns

```regex
# AWS Access Key
AKIA[0-9A-Z]{16}

# GitHub Token
ghp_[a-zA-Z0-9]{36}

# Generic API Key
[aA][pP][iI][-_]?[kK][eE][yY].*['\"][a-zA-Z0-9]{20,}['\"]

# Private Key
-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----
```

### SQL Injection Patterns

```regex
# String concatenation in queries
query.*\+.*\$|query.*\+.*request|query.*\+.*params

# f-string SQL (Python)
f['\"].*SELECT.*\{|f['\"].*INSERT.*\{|f['\"].*UPDATE.*\{
```

## Output Format

```markdown
## Security Scan Report

### 🔴 Critical (Immediate Action Required)
| Finding | Location | Description | Remediation |
|---------|----------|-------------|-------------|

### 🟠 High Severity
| Finding | Location | Description | Remediation |
|---------|----------|-------------|-------------|

### 🟡 Medium Severity
| Finding | Location | Description | Remediation |
|---------|----------|-------------|-------------|

### 🔵 Low Severity / Informational
| Finding | Location | Description | Remediation |
|---------|----------|-------------|-------------|

### ✅ Positive Findings
- Security measures properly implemented
- Good practices observed
```

## Remediation Guidelines

1. **Secrets**: Use environment variables or secret managers
2. **SQL Injection**: Use parameterized queries
3. **XSS**: Sanitize and escape output
4. **CSRF**: Implement CSRF tokens
5. **Auth Issues**: Use established auth libraries
