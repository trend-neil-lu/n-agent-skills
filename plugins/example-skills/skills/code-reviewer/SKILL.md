---
name: code-reviewer
description: Reviews code for best practices, potential bugs, security issues, and performance improvements. Use when reviewing code changes, PRs, or analyzing code quality. Triggers on 'review code', 'code review', 'check this code', or 'analyze code quality'.
allowed-tools: Read, Grep, Glob, Bash
---

# Code Reviewer Skill

Provides comprehensive code review with actionable feedback.

## Review Checklist

### Code Quality

- [ ] Follows project coding standards
- [ ] Clear and descriptive naming
- [ ] Appropriate comments where needed
- [ ] No code duplication (DRY principle)
- [ ] Single responsibility principle

### Security

- [ ] No hardcoded secrets or credentials
- [ ] Input validation present
- [ ] Safe handling of user data
- [ ] No SQL injection vulnerabilities
- [ ] XSS prevention measures

### Performance

- [ ] Efficient algorithms used
- [ ] No unnecessary loops or iterations
- [ ] Proper caching strategies
- [ ] Optimized database queries
- [ ] Memory management considerations

### Error Handling

- [ ] Proper exception handling
- [ ] Meaningful error messages
- [ ] Graceful degradation
- [ ] Logging for debugging

### Testing

- [ ] Unit tests present
- [ ] Edge cases covered
- [ ] Test coverage adequate

## Output Format

Provide feedback in this structure:

```markdown
## Code Review Summary

### Critical Issues 🔴
- Issue description and location
- Recommended fix

### Warnings ⚠️
- Potential problems
- Suggested improvements

### Suggestions 💡
- Best practice recommendations
- Code style improvements

### Positive Notes ✅
- Well-implemented patterns
- Good practices observed
```
