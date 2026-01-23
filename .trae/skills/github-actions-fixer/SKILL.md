---
name: "github-actions-fixer"
description: "Fixes GitHub Actions workflow syntax errors in conditional expressions. Invoke when encountering expression syntax errors or workflow validation failures."
---

# GitHub Actions Fixer

This skill fixes common syntax errors in GitHub Actions workflow files, particularly in conditional expressions.

## Common Error: Conditional Expression Contains Literal Text

**Error Message:**
```
Conditional expression contains literal text outside replacement tokens. This will cause the expression to always evaluate to truthy. Did you mean to put the entire expression inside ${{ }}?
```

**Problem:**
The comparison operator or other expression parts are outside the `${{ }}` wrapper.

**Incorrect:**
```yaml
if: ${{ github.event.repository.owner.id }} == ${{ github.event.sender.id }}
```

**Correct:**
```yaml
if: ${{ github.event.repository.owner.id == github.event.sender.id }}
```

## Fix Rules

1. **Single Expression Wrapper**: Put the entire expression inside a single `${{ }}` block
2. **No Splitting**: Do not split expressions across multiple `${{ }}` blocks
3. **Complete Logic**: Ensure all operators, variables, and values are within the same wrapper

## Common Patterns

### Equality Comparison
```yaml
# Wrong
if: ${{ steps.init.outputs.status }} == 'success'

# Right
if: ${{ steps.init.outputs.status == 'success' }}
```

### Logical AND
```yaml
# Wrong
if: ${{ steps.codes.outputs.status }} == 'success' && ${{ !cancelled() }}

# Right
if: ${{ steps.codes.outputs.status == 'success' && !cancelled() }}
```

### Logical OR
```yaml
# Wrong
if: ${{ github.event_name }} == 'push' || ${{ github.event_name }} == 'pull_request'

# Right
if: ${{ github.event_name == 'push' || github.event_name == 'pull_request' }}
```

### Environment Variable Comparison
```yaml
# Wrong
if: ${{ env.UPLOAD_RELEASE }} == 'true'

# Right
if: ${{ env.UPLOAD_RELEASE == 'true' }}
```

## Additional GitHub Actions Syntax Tips

### String Comparison
```yaml
if: ${{ github.event_name == 'workflow_dispatch' }}
```

### Numeric Comparison
```yaml
if: ${{ github.event.repository.owner.id == github.event.sender.id }}
```

### Boolean Logic
```yaml
if: ${{ !cancelled() && success() }}
```

### Function Calls
```yaml
if: ${{ contains(github.event.head_commit.message, '[skip ci]') }}
```

## When to Use This Skill

Invoke this skill when:
- GitHub Actions workflow validation fails with expression syntax errors
- Linting tools report "literal text outside replacement tokens" errors
- Conditional expressions are not evaluating as expected
- Workflow steps are running when they shouldn't (or vice versa)

## Implementation Steps

1. Identify the problematic conditional expression
2. Locate the error in the workflow file (usually in `if:`, `env:`, or step conditions)
3. Ensure the entire expression is wrapped in a single `${{ }}`
4. Verify all operators and values are inside the wrapper
5. Test the workflow to confirm the fix
