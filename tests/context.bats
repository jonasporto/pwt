#!/usr/bin/env bats
# Tests for pwt context command
# Verifies context display

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
# context basic
# ============================================

@test "pwt context shows project info" {
    cd "$TEST_REPO"
    run "$PWT_BIN" context
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}

@test "pwt context shows markdown format" {
    cd "$TEST_REPO"
    run "$PWT_BIN" context
    [ "$status" -eq 0 ]
    # Should contain markdown headers
    [[ "$output" == *"#"* ]]
}

@test "pwt context shows main app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" context
    [ "$status" -eq 0 ]
    [[ "$output" == *"Main App"* ]] || [[ "$output" == *"$TEST_REPO"* ]]
}

@test "pwt context shows worktrees directory" {
    cd "$TEST_REPO"
    run "$PWT_BIN" context
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktrees"* ]] || [[ "$output" == *"worktrees"* ]]
}

# ============================================
# context with worktrees
# ============================================

@test "pwt context lists active worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-CTX HEAD

    run "$PWT_BIN" context
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-CTX"* ]]
}

@test "pwt context shows worktree table" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-TBL HEAD

    run "$PWT_BIN" context
    [ "$status" -eq 0 ]
    # Should contain markdown table
    [[ "$output" == *"|"* ]]
}

# ============================================
# context via project prefix
# ============================================

@test "pwt <project> context works from anywhere" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project context
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}
