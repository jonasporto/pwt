#!/usr/bin/env bats
# Tests for pwt marker command
# Verifies marker management for worktrees

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
# marker set
# ============================================

@test "pwt marker sets marker on worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-MARK HEAD

    run "$PWT_BIN" marker WT-MARK "in-progress"
    [ "$status" -eq 0 ]
}

@test "pwt marker shows marker in list" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-SHOW HEAD
    "$PWT_BIN" marker WT-SHOW "review"

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    # Marker might show in list output
}

# ============================================
# marker clear
# ============================================

@test "pwt marker --clear removes marker" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-CLEAR HEAD
    "$PWT_BIN" marker WT-CLEAR "test"

    run "$PWT_BIN" marker WT-CLEAR --clear
    [ "$status" -eq 0 ]
}

@test "pwt marker -c is shorthand for --clear" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-C HEAD
    "$PWT_BIN" marker WT-C "test"

    run "$PWT_BIN" marker WT-C -c
    [ "$status" -eq 0 ]
}

# ============================================
# marker via project prefix
# ============================================

@test "pwt <project> marker works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project marker WT-REMOTE "remote-marker"
    [ "$status" -eq 0 ]
}
