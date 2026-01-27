#!/usr/bin/env bash
# Test helper for pwt tests
# Sets up the environment and provides utility functions

# Get the path to pwt binary and module library
PWD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PWT_BIN="$PWD_DIR/bin/pwt"
PWT_LIB_DIR="$PWD_DIR/lib/pwt"
PWT_STATUS_MODULE="$PWT_LIB_DIR/status.sh"

# Create a temporary directory for each test
setup_test_env() {
    export TEST_TEMP_DIR=$(mktemp -d)
    export HOME="$TEST_TEMP_DIR/home"
    # Use PWT_DIR env var for sandbox testing (pwt respects this)
    export PWT_DIR="$TEST_TEMP_DIR/pwt"
    mkdir -p "$HOME"
    mkdir -p "$PWT_DIR/projects"
    echo '{}' > "$PWT_DIR/meta.json"

    # Create a temporary git repo for testing
    export TEST_REPO="$TEST_TEMP_DIR/test-repo"
    mkdir -p "$TEST_REPO"
    git init -q "$TEST_REPO"
    cd "$TEST_REPO"
    git config user.email "test@test.com"
    git config user.name "Test User"
    touch README.md
    git add README.md
    git commit -q -m "Initial commit"
}

# Clean up temporary directory after each test
teardown_test_env() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Source specific functions from pwt for unit testing
# This extracts a function from pwt without running the whole script
source_pwt_function() {
    local func_name="$1"
    # Extract colors and the function definition from pwt
    eval "$(grep -E '^(RED|GREEN|YELLOW|BLUE|NC)=' "$PWT_BIN" | head -5)"
    eval "$(sed -n "/^$func_name()/,/^}/p" "$PWT_BIN")"
}

# Source multiple functions at once
source_pwt_functions() {
    for func in "$@"; do
        source_pwt_function "$func"
    done
}

# Assert function output equals expected
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected' but got '$actual'}"

    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $message" >&2
        return 1
    fi
}

# Assert function returns true (exit 0)
assert_success() {
    local message="${1:-Expected success but got failure}"
    if [ "$status" -ne 0 ]; then
        echo "FAIL: $message (exit code: $status)" >&2
        return 1
    fi
}

# Assert function returns false (exit non-zero)
assert_failure() {
    local message="${1:-Expected failure but got success}"
    if [ "$status" -eq 0 ]; then
        echo "FAIL: $message" >&2
        return 1
    fi
}
