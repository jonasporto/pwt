#!/usr/bin/env bats
# Tests for pwt fix-port command
# Verifies port conflict detection and resolution

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
# fix-port basic
# ============================================

@test "pwt fix-port shows port is free when not occupied" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-FREE HEAD

    run "$PWT_BIN" fix-port WT-FREE
    [ "$status" -eq 0 ]
    [[ "$output" == *"free"* ]] || [[ "$output" == *"No changes"* ]]
}

@test "pwt fix-port requires worktree name from outside worktree" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project fix-port
    [ "$status" -ne 0 ]
    [[ "$output" == *"not specified"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "pwt fix-port fails for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" fix-port NONEXISTENT
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# ============================================
# fix-port detection from pwd
# ============================================

@test "pwt fix-port detects worktree from pwd" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PWD HEAD

    cd "$TEST_WORKTREES/WT-PWD"
    run "$PWT_BIN" fix-port
    [ "$status" -eq 0 ]
    [[ "$output" == *"free"* ]] || [[ "$output" == *"No changes"* ]]
}

# ============================================
# fix-port via project prefix
# ============================================

@test "pwt <project> fix-port works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project fix-port WT-REMOTE
    [ "$status" -eq 0 ]
}

# ============================================
# fix-port port validation
# ============================================

@test "pwt fix-port reads port from metadata" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-META HEAD

    # Get the port
    local port=$("$PWT_BIN" meta show WT-META | grep -o '"port": [0-9]*' | grep -o '[0-9]*')

    run "$PWT_BIN" fix-port WT-META
    [ "$status" -eq 0 ]
    # Port should be mentioned in output
    [[ "$output" == *"$port"* ]] || [[ "$output" == *"free"* ]]
}
