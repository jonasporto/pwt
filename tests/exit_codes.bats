#!/usr/bin/env bats
# Tests for pwt exit codes
# Exit codes: 0=success, 1=general error, 2=usage error, 3=not found, 4=conflict

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
# Exit code constants verification
# ============================================

@test "EXIT_SUCCESS is 0" {
    cd "$TEST_REPO"
    run "$PWT_BIN" version
    [ "$status" -eq 0 ]
}

@test "EXIT_USAGE (2) for unknown command" {
    cd "$TEST_REPO"
    run "$PWT_BIN" notarealcommand_xyz
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "EXIT_USAGE (2) for unknown option" {
    cd "$TEST_REPO"
    run "$PWT_BIN" --notarealoption
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "EXIT_NOT_FOUND (3) for nonexistent worktree in info" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info nonexistent_worktree_xyz
    [ "$status" -eq 3 ] || [ "$status" -eq 1 ]  # Allow 1 for backwards compatibility
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"No worktree"* ]]
}

@test "help command returns success (0)" {
    run "$PWT_BIN" help
    [ "$status" -eq 0 ]
}

@test "--help flag returns success (0)" {
    run "$PWT_BIN" --help
    [ "$status" -eq 0 ]
}

@test "-h flag returns success (0)" {
    run "$PWT_BIN" -h
    [ "$status" -eq 0 ]
}

@test "list command returns success in configured project" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
}

@test "doctor command returns success" {
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
}

# ============================================
# Exit code documentation in help
# ============================================

@test "exit codes are defined in script" {
    # Verify the exit code constants exist in the script
    grep -q "EXIT_SUCCESS=0" "$PWT_BIN"
    grep -q "EXIT_ERROR=1" "$PWT_BIN"
    grep -q "EXIT_USAGE=2" "$PWT_BIN"
    grep -q "EXIT_NOT_FOUND=3" "$PWT_BIN"
    grep -q "EXIT_CONFLICT=4" "$PWT_BIN"
}

# ============================================
# Edge cases
# ============================================

@test "no arguments shows help and returns success" {
    cd "$TEST_REPO"
    run "$PWT_BIN"
    # With a configured project, no args may show list or help
    [ "$status" -eq 0 ]
}

@test "empty project flag is an error" {
    run "$PWT_BIN" --project
    # Should error (missing project name)
    [ "$status" -ne 0 ]
}
