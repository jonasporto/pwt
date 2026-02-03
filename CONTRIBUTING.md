# Contributing to pwt

Thanks for your interest in contributing to pwt!

## How to Contribute

### 1. Open an Issue First

Before writing any code, please [open an issue](https://github.com/jonasporto/pwt/issues/new) describing:

- **Bug reports**: What happened, what you expected, and steps to reproduce
- **Feature requests**: What you'd like to see and why it would be useful
- **Questions**: If you're unsure about something

### 2. Wait for Feedback

Maintainers will review your issue and provide feedback. This helps:

- Avoid duplicate work
- Align on the approach before code is written
- Ensure the change fits the project's direction

### 3. Open a Pull Request

Once your issue is approved:

1. Fork the repository
2. Create a branch for your changes
3. Make your changes
4. Run tests: `bats tests/`
5. Open a PR referencing the issue (e.g., `Fixes #123`)

**Note:** PRs without a linked issue will be automatically closed.

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/pwt.git
cd pwt

# Run tests
bats tests/

# Run a specific test file
bats tests/commands.bats

# Run pwt from source
./bin/pwt help
```

## Code Style

- Functions: `snake_case`
- Variables: `UPPER_SNAKE_CASE` for exports, `lower_snake_case` for locals
- Always provide default values for exported variables: `export VAR="${VAR:-}"`
- Add tests for new functionality

## Questions?

Feel free to open an issue if you have questions about contributing.
