---
name: doc-generator
description: Generates documentation for code including API docs, README files, function documentation, and usage examples. Use when creating documentation, generating API references, or documenting code. Triggers on 'generate docs', 'create documentation', 'document this', or 'write README'.
allowed-tools: Read, Grep, Glob, Write
---

# Documentation Generator Skill

Creates comprehensive, well-structured documentation for codebases.

## Documentation Types

### 1. API Documentation

- Endpoint descriptions
- Request/response formats
- Authentication requirements
- Error codes and handling
- Usage examples

### 2. Function/Class Documentation

- Purpose and description
- Parameters with types
- Return values
- Exceptions/errors
- Usage examples

### 3. README Files

- Project overview
- Installation instructions
- Quick start guide
- Configuration options
- Contributing guidelines

### 4. Architecture Documentation

- System overview
- Component relationships
- Data flow diagrams
- Technology stack

## Documentation Standards

### JSDoc Style (JavaScript/TypeScript)

```javascript
/**
 * Brief description of the function
 *
 * @param {string} name - Parameter description
 * @param {Object} options - Configuration options
 * @returns {Promise<Result>} Description of return value
 * @throws {Error} When something goes wrong
 * @example
 * const result = await myFunction('test', { flag: true });
 */
```

### Docstring Style (Python)

```python
def my_function(name: str, options: dict) -> Result:
    """
    Brief description of the function.

    Args:
        name: Parameter description
        options: Configuration options

    Returns:
        Description of return value

    Raises:
        ValueError: When input is invalid

    Example:
        >>> result = my_function('test', {'flag': True})
    """
```

### Go Documentation

```go
// MyFunction does something useful.
// It takes a name and options as parameters.
//
// Example:
//
//	result, err := MyFunction("test", opts)
func MyFunction(name string, opts Options) (*Result, error) {
```

## Best Practices

1. **Be concise** - Get to the point quickly
2. **Include examples** - Show, don't just tell
3. **Keep updated** - Documentation should match code
4. **Use consistent formatting** - Follow project standards
5. **Link related docs** - Cross-reference when helpful
