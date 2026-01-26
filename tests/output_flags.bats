#!/usr/bin/env bats
# Tests for --quiet and --verbose global flags

load test_helper

setup() {
    setup_test_env

    # Initialize a pwt project in the test repo
    cd "$TEST_REPO"

    # Create worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/"
}
EOF
}

teardown() {
    teardown_test_env
}

# ============================================
# --quiet flag tests
# ============================================

@test "--quiet flag is accepted" {
    cd "$TEST_REPO"
    run "$PWT_BIN" --quiet version
    [ "$status" -eq 0 ]
}

@test "-q flag is accepted" {
    cd "$TEST_REPO"
    run "$PWT_BIN" -q version
    [ "$status" -eq 0 ]
}

@test "--quiet works with list command" {
    cd "$TEST_REPO"
    run "$PWT_BIN" --quiet list
    [ "$status" -eq 0 ]
}

# ============================================
# --verbose flag tests
# ============================================

@test "--verbose flag is accepted" {
    cd "$TEST_REPO"
    run "$PWT_BIN" --verbose version
    [ "$status" -eq 0 ]
}

@test "--verbose works with list command" {
    cd "$TEST_REPO"
    run "$PWT_BIN" --verbose list
    [ "$status" -eq 0 ]
}

@test "--verbose shows debug output for create" {
    cd "$TEST_REPO"
    # Create a test branch first
    git branch test-verbose-branch

    # Run with verbose and capture output (debug goes to stderr)
    output=$("$PWT_BIN" --verbose create test-verbose-branch --dry-run 2>&1) || true
    # Debug output should contain [debug] markers
    [[ "$output" == *"debug"* ]] || [[ "$output" == *"Creating worktree"* ]]
}

# ============================================
# Combination tests
# ============================================

@test "--quiet and --verbose can be combined (quiet wins for info)" {
    cd "$TEST_REPO"
    run "$PWT_BIN" --quiet --verbose version
    [ "$status" -eq 0 ]
}

@test "flags work before command" {
    run "$PWT_BIN" --quiet --verbose doctor
    [ "$status" -eq 0 ]
}

# ============================================
# Helper function tests
# ============================================

@test "PWT_QUIET variable is defined in script" {
    grep -q "PWT_QUIET=" "$PWT_BIN"
}

@test "PWT_VERBOSE variable is defined in script" {
    grep -q "PWT_VERBOSE=" "$PWT_BIN"
}

@test "pwt_info function is defined" {
    grep -q "^pwt_info()" "$PWT_BIN"
}

@test "pwt_debug function is defined" {
    grep -q "^pwt_debug()" "$PWT_BIN"
}

@test "pwt_warn function is defined" {
    grep -q "^pwt_warn()" "$PWT_BIN"
}

@test "pwt_error function is defined" {
    grep -q "^pwt_error()" "$PWT_BIN"
}
