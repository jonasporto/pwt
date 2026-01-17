# pwt Tests

Unit and integration tests for pwt using [bats-core](https://github.com/bats-core/bats-core).

## Setup

### Install bats-core

**macOS:**
```bash
brew install bats-core
```

**Ubuntu/Debian:**
```bash
sudo apt install bats
```

**From source:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local
```

## Running Tests

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/extract_worktree_name.bats

# Run with verbose output
bats -v tests/

# Run with TAP output (for CI)
bats --tap tests/
```

## Test Structure

| File | Description |
|------|-------------|
| `test_helper.bash` | Common setup/teardown and utilities |
| `extract_worktree_name.bats` | Tests for branch name extraction |
| `helpers.bats` | Tests for helper functions (has_lsof, require_cmd, etc.) |
| `commands.bats` | Integration tests for pwt commands |

## Writing Tests

Tests use the bats syntax:

```bash
@test "description of test" {
    run some_command
    [ "$status" -eq 0 ]
    [ "$output" = "expected" ]
}
```

Use the helper functions from `test_helper.bash`:

```bash
setup() {
    setup_test_env          # Creates temp dir, HOME, git repo
    source_pwt_function foo # Extract function from pwt
}

teardown() {
    teardown_test_env       # Cleans up temp dir
}
```

## CI Integration

For GitHub Actions, add to `.github/workflows/test.yml`:

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Install bats
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get update && sudo apt-get install -y bats
          else
            brew install bats-core
          fi

      - name: Install dependencies
        run: |
          if [[ "$RUNNER_OS" == "Linux" ]]; then
            sudo apt-get install -y jq lsof
          fi

      - name: Run tests
        run: bats tests/
```
