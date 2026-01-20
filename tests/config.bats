#!/usr/bin/env bats
# Tests for pwt config command
# Verifies configuration get/set

load test_helper

setup() {
    setup_test_env

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

    # Add a commit
    cd "$TEST_REPO"
    echo "content" > file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    teardown_test_env
}

# ============================================
# config show
# ============================================

@test "pwt config shows current settings" {
    cd "$TEST_REPO"
    run "$PWT_BIN" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}

@test "pwt config show displays project name" {
    cd "$TEST_REPO"
    run "$PWT_BIN" config show
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project"* ]]
}

@test "pwt config shows main_app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"main_app"* ]] || [[ "$output" == *"$TEST_REPO"* ]]
}

@test "pwt config shows worktrees_dir" {
    cd "$TEST_REPO"
    run "$PWT_BIN" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"worktrees_dir"* ]] || [[ "$output" == *"worktrees"* ]]
}

@test "pwt config shows branch_prefix" {
    cd "$TEST_REPO"
    run "$PWT_BIN" config
    [ "$status" -eq 0 ]
    [[ "$output" == *"branch_prefix"* ]] || [[ "$output" == *"test/"* ]]
}

# ============================================
# config get (key only)
# ============================================

@test "pwt config <key> retrieves specific value" {
    cd "$TEST_REPO"
    run "$PWT_BIN" config branch_prefix
    [ "$status" -eq 0 ]
    [[ "$output" == *"test/"* ]]
}

# ============================================
# config set (key value)
# ============================================

@test "pwt config <key> <value> updates value" {
    cd "$TEST_REPO"
    run "$PWT_BIN" config branch_prefix "feature/"
    [ "$status" -eq 0 ]

    # Verify it was updated
    run "$PWT_BIN" config branch_prefix
    [[ "$output" == *"feature/"* ]]
}

# ============================================
# config requires project
# ============================================

@test "pwt config fails outside project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" config
    [ "$status" -ne 0 ]
    [[ "$output" == *"No project"* ]] || [[ "$output" == *"project"* ]]
}

# ============================================
# config via project prefix
# ============================================

@test "pwt <project> config works from anywhere" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project config
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}
