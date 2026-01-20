#!/usr/bin/env bats
# Tests for pwt conflicts command
# Verifies conflict detection between worktrees

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
# conflicts basic
# ============================================

@test "pwt conflicts runs without error" {
    cd "$TEST_REPO"
    run "$PWT_BIN" conflicts
    [ "$status" -eq 0 ]
}

@test "pwt conflicts shows no conflicts for empty worktrees" {
    cd "$TEST_REPO"
    run "$PWT_BIN" conflicts
    [ "$status" -eq 0 ]
}

# ============================================
# conflicts with worktrees
# ============================================

@test "pwt conflicts analyzes worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-C1 HEAD
    "$PWT_BIN" create WT-C2 HEAD

    run "$PWT_BIN" conflicts
    [ "$status" -eq 0 ]
}

@test "pwt conflicts compares specific pair" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-A HEAD
    "$PWT_BIN" create WT-B HEAD

    run "$PWT_BIN" conflicts WT-A WT-B
    [ "$status" -eq 0 ]
}

# ============================================
# conflicts detection
# ============================================

@test "pwt conflicts detects modified same file" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-MOD1 HEAD
    "$PWT_BIN" create WT-MOD2 HEAD

    # Modify same file in both worktrees
    echo "change1" >> "$TEST_WORKTREES/WT-MOD1/file.txt"
    echo "change2" >> "$TEST_WORKTREES/WT-MOD2/file.txt"

    run "$PWT_BIN" conflicts WT-MOD1 WT-MOD2
    [ "$status" -eq 0 ]
}

# ============================================
# conflicts via project prefix
# ============================================

@test "pwt <project> conflicts works from anywhere" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project conflicts
    [ "$status" -eq 0 ]
}
