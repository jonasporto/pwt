# CLAUDE.md - pwt Development Guide

This file provides guidance for AI assistants working on the pwt codebase.

## Project Overview

`pwt` (Power Worktrees) is a bash tool for managing git worktrees across multiple projects. It provides:
- Worktree creation/removal with isolated configurations
- Port allocation for development servers
- Custom command execution via Pwtfile
- Project configuration management

## Architecture

```
bin/pwt           # Main bash script (~7000 lines)
tests/*.bats      # BATS test files
completions/      # Shell completion scripts
```

## Testing

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System):

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/pwtfile.bats

# Run tests matching pattern
bats tests/pwtfile.bats -f "PWT_ARGS"
```

## Development Conventions

### Environment Variables

**CRITICAL:** All `PWT_*` variables must be exported with default values in `run_pwtfile()` to avoid "unbound variable" errors when Pwtfiles use `set -u` (strict mode).

```bash
# CORRECT - always provide default
export PWT_ARGS="${PWT_ARGS:-}"

# WRONG - can break Pwtfiles using strict mode
export PWT_ARGS  # May be unset!
```

**Why this matters:**
- Pwtfiles are user-provided scripts that may use `set -u` for safety
- Variables like `$PWT_ARGS` are iterated with `for arg in $PWT_ARGS`
- If undefined, bash throws "unbound variable" error in strict mode

**Required variables (see `run_pwtfile()`):**
- `PWT_PORT` - Allocated port number
- `PWT_WORKTREE` - Worktree name
- `PWT_WORKTREE_PATH` - Full path to worktree
- `PWT_BRANCH` - Git branch name
- `PWT_TICKET` - Extracted ticket number
- `PWT_PROJECT` - Project name
- `PWT_ARGS` - Arguments passed to custom commands

### Adding New PWT_* Variables

When adding new variables that Pwtfiles might use:

1. Add default export in `run_pwtfile()`:
   ```bash
   export PWT_NEWVAR="${PWT_NEWVAR:-}"
   ```

2. Add test in `tests/pwtfile.bats`:
   ```bash
   @test "PWT_NEWVAR is always defined" {
       # Test with set -u in Pwtfile
   }
   ```

3. Document in README.md "Available Variables" section

### Error Handling

- Pwtfile commands run in subshells - errors don't kill pwt
- Always check `$?` after critical operations
- Use `|| true` for optional operations that may fail

## Code Style

- Functions: `snake_case`
- Variables: `UPPER_SNAKE_CASE` for exports, `lower_snake_case` for locals
- Comments: Explain "why", not "what"
- Error messages: Include context (worktree name, path, etc.)

## Common Tasks

### Running pwt from source

```bash
# Direct execution
./bin/pwt <command>

# Or symlink during development
ln -sf $(pwd)/bin/pwt ~/.local/bin/pwt
```

### Debugging

```bash
# Enable debug output
PWT_DEBUG=1 pwt <command>

# Trace bash execution
bash -x bin/pwt <command>
```
