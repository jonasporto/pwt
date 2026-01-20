#!/usr/bin/env bats
# Tests for pwt tree command
# Verifies tree view of worktrees

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
# tree basic
# ============================================

@test "pwt tree shows worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-TREE HEAD

    run "$PWT_BIN" tree
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-TREE"* ]]
}

@test "pwt tree shows main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" tree
    [ "$status" -eq 0 ]
    [[ "$output" == *"@"* ]] || [[ "$output" == *"main"* ]]
}

# ============================================
# tree options
# ============================================

@test "pwt tree --ports shows port numbers" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PORTS HEAD

    run "$PWT_BIN" tree --ports
    [ "$status" -eq 0 ]
    # Should show port number (4 digits)
    [[ "$output" =~ [0-9]{4} ]]
}

@test "pwt tree -p is shorthand for --ports" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-P HEAD

    run "$PWT_BIN" tree -p
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]{4} ]]
}

# ============================================
# tree with multiple worktrees
# ============================================

@test "pwt tree shows all worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-T1 HEAD
    "$PWT_BIN" create WT-T2 HEAD

    run "$PWT_BIN" tree
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-T1"* ]]
    [[ "$output" == *"WT-T2"* ]]
}

# ============================================
# tree via project prefix
# ============================================

@test "pwt <project> tree works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project tree
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-REMOTE"* ]]
}
