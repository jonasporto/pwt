#!/usr/bin/env bats
# Tests for pwt diff command
# Verifies diff between worktrees

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
# diff basic
# ============================================

@test "pwt diff requires worktree argument" {
    cd "$TEST_REPO"
    run "$PWT_BIN" diff
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt diff compares worktree to main app" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DIFF HEAD

    # Make a change in worktree
    echo "new content" > "$TEST_WORKTREES/WT-DIFF/newfile.txt"

    run "$PWT_BIN" diff WT-DIFF
    [ "$status" -eq 0 ]
}

@test "pwt diff defaults second arg to @" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DEFAULT HEAD

    run "$PWT_BIN" diff WT-DEFAULT
    [ "$status" -eq 0 ]
}

# ============================================
# diff between worktrees
# ============================================

@test "pwt diff compares two worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-A HEAD
    "$PWT_BIN" create WT-B HEAD

    # Make different changes
    echo "content A" > "$TEST_WORKTREES/WT-A/diff.txt"
    echo "content B" > "$TEST_WORKTREES/WT-B/diff.txt"

    run "$PWT_BIN" diff WT-A WT-B
    [ "$status" -eq 0 ]
}

@test "pwt diff with @ as first arg" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-AT HEAD

    run "$PWT_BIN" diff @ WT-AT
    [ "$status" -eq 0 ]
}

# ============================================
# diff errors
# ============================================

@test "pwt diff fails for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" diff NONEXISTENT
    [ "$status" -ne 0 ]
}

# ============================================
# diff via project prefix
# ============================================

@test "pwt <project> diff works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project diff WT-REMOTE
    [ "$status" -eq 0 ]
}
