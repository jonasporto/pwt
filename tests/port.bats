#!/usr/bin/env bats
# Tests for pwt port command
# Verifies port retrieval

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
# port basic
# ============================================

@test "pwt port returns port number for worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PORT HEAD

    run "$PWT_BIN" port WT-PORT
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "pwt port detects worktree from pwd" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PWD HEAD

    cd "$TEST_WORKTREES/WT-PWD"
    run "$PWT_BIN" port
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "pwt port fails outside worktree without argument" {
    cd "$TEST_REPO"
    run "$PWT_BIN" port
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not in a worktree"* ]] || [[ "$output" == *"Error"* ]]
}

@test "pwt port fails for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" port NONEXISTENT
    [ "$status" -ne 0 ]
}

# ============================================
# port consistency
# ============================================

@test "pwt port returns same value as meta show" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-META HEAD

    local port_cmd=$("$PWT_BIN" port WT-META)
    local meta_port=$("$PWT_BIN" meta show WT-META | grep -o '"port": [0-9]*' | grep -o '[0-9]*')

    [ "$port_cmd" = "$meta_port" ]
}

# ============================================
# port via project prefix
# ============================================

@test "pwt <project> port works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project port WT-REMOTE
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}
