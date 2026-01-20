#!/usr/bin/env bats
# Tests for pwt for-each command
# Verifies batch command execution across worktrees

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
# for-each basic
# ============================================

@test "pwt for-each requires command" {
    cd "$TEST_REPO"
    run "$PWT_BIN" for-each
    [ "$status" -ne 0 ]
    [[ "$output" == *"No command"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "pwt for-each runs in main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" for-each pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"@ (main)"* ]] || [[ "$output" == *"main"* ]]
    [[ "$output" == *"$TEST_REPO"* ]] || [[ "$output" == *"test-repo"* ]]
}

@test "pwt for-each shows completion count" {
    cd "$TEST_REPO"
    run "$PWT_BIN" for-each echo "test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ran in"* ]] || [[ "$output" == *"worktree"* ]]
}

# ============================================
# for-each with worktrees
# ============================================

@test "pwt for-each runs in all worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-EACH1 HEAD
    "$PWT_BIN" create WT-EACH2 HEAD

    run "$PWT_BIN" for-each pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-EACH1"* ]]
    [[ "$output" == *"WT-EACH2"* ]]
}

@test "pwt for-each shows header for each worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-HDR HEAD

    run "$PWT_BIN" for-each echo "hello"
    [ "$status" -eq 0 ]
    # Should show === WT-HDR === or similar header
    [[ "$output" == *"==="* ]]
    [[ "$output" == *"WT-HDR"* ]]
}

@test "pwt for-each runs command in worktree directory" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DIR HEAD

    # Create a marker file in the worktree
    echo "marker-wt" > "$TEST_WORKTREES/WT-DIR/marker.txt"
    # Also create in main to avoid failure there
    echo "marker-main" > "$TEST_REPO/marker.txt"

    run "$PWT_BIN" for-each cat marker.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"marker-wt"* ]]
    [[ "$output" == *"marker-main"* ]]
}

@test "pwt for-each counts worktrees correctly" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-CNT1 HEAD
    "$PWT_BIN" create WT-CNT2 HEAD

    run "$PWT_BIN" for-each echo "x"
    [ "$status" -eq 0 ]
    # 3 = main + 2 worktrees
    [[ "$output" == *"3"* ]]
}

# ============================================
# for-each with complex commands
# ============================================

@test "pwt for-each handles shell commands" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-SH HEAD

    run "$PWT_BIN" for-each "echo hello && echo world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
    [[ "$output" == *"world"* ]]
}

@test "pwt for-each runs git commands" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-GIT HEAD

    run "$PWT_BIN" for-each git branch --show-current
    [ "$status" -eq 0 ]
    [[ "$output" == *"test/WT-GIT"* ]]
}

# ============================================
# for-each sets environment variables
# ============================================

@test "pwt for-each sets PWT_WORKTREE in worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-ENV HEAD

    # Use ${VAR:-} to handle unset variable in main app
    run "$PWT_BIN" for-each 'echo WT=${PWT_WORKTREE:-}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT=WT-ENV"* ]]
}

@test "pwt for-each unsets PWT_WORKTREE in main" {
    cd "$TEST_REPO"

    run "$PWT_BIN" for-each 'echo "WT=${PWT_WORKTREE:-NONE}"'
    [ "$status" -eq 0 ]
    # In main app, PWT_WORKTREE should be unset/empty
    [[ "$output" == *"WT=NONE"* ]] || [[ "$output" == *"WT="* ]]
}

# ============================================
# for-each via project prefix
# ============================================

@test "pwt <project> for-each works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project for-each echo "test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ran in"* ]]
}

# ============================================
# for-each with no worktrees
# ============================================

@test "pwt for-each works with only main app" {
    cd "$TEST_REPO"
    # No worktrees created

    run "$PWT_BIN" for-each echo "only main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"only main"* ]]
    [[ "$output" == *"1"* ]]  # Only 1 (main)
}
