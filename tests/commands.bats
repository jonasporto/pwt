#!/usr/bin/env bats
# Integration tests for pwt commands

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
# pwt list tests
# ============================================

@test "pwt list shows no worktrees when empty" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No worktrees"* ]] || [[ "$output" == *"worktrees"* ]]
}

@test "pwt list --porcelain returns valid JSON" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --porcelain

    # Should be valid JSON (jq won't fail)
    echo "$output" | jq . > /dev/null 2>&1
    [ "$?" -eq 0 ]
}

@test "pwt list --porcelain includes project name" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --porcelain

    # Should contain project field
    local project=$(echo "$output" | jq -r '.project')
    [ -n "$project" ]
}

# ============================================
# pwt info tests
# ============================================

@test "pwt info shows error for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"No worktree"* ]]
}

# ============================================
# pwt doctor tests
# ============================================

@test "pwt doctor runs without error" {
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"jq"* ]]
}

@test "pwt doctor checks git" {
    run "$PWT_BIN" doctor
    [[ "$output" == *"git:"* ]]
}

@test "pwt doctor checks jq" {
    run "$PWT_BIN" doctor
    [[ "$output" == *"jq:"* ]]
}

# ============================================
# pwt help tests
# ============================================

@test "pwt help shows usage" {
    run "$PWT_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"pwt"* ]]
}

@test "pwt --help shows usage" {
    run "$PWT_BIN" --help
    [ "$status" -eq 0 ]
}

@test "pwt with no args shows help or list" {
    cd "$TEST_REPO"
    run "$PWT_BIN"
    # Should either show help or list (depending on context)
    [ "$status" -eq 0 ]
}

# ============================================
# pwt version tests
# ============================================

@test "pwt version shows version number" {
    run "$PWT_BIN" version
    [ "$status" -eq 0 ]
    # Should output something (version or message)
    [ -n "$output" ]
}

@test "pwt --version shows version number" {
    run "$PWT_BIN" --version
    [ "$status" -eq 0 ]
}
