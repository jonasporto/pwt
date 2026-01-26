#!/usr/bin/env bats
# Tests for --help / -h flags on commands

load test_helper

setup() {
    setup_test_env

    cd "$TEST_REPO"
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

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
# Core commands --help tests
# ============================================

@test "pwt info --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt info -h shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt doctor --help shows usage" {
    run "$PWT_BIN" doctor --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt doctor -h shows usage" {
    run "$PWT_BIN" doctor -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt diff --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" diff --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt run --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt for-each --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" for-each --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt cd --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ============================================
# Commands that already had --help
# ============================================

@test "pwt create --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt list --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"pwt list"* ]]
}

@test "pwt tree --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" tree --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"tree"* ]]
}

# ============================================
# Help content validation
# ============================================

@test "info help includes usage line" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info --help
    [[ "$output" == *"Usage: pwt info"* ]]
}

@test "doctor help includes checks section" {
    run "$PWT_BIN" doctor --help
    [[ "$output" == *"Checks performed"* ]]
}

@test "diff help includes examples" {
    cd "$TEST_REPO"
    run "$PWT_BIN" diff --help
    [[ "$output" == *"Examples"* ]]
}
