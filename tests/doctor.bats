#!/usr/bin/env bats
# Tests for pwt doctor command
# Verifies health check functionality

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
# doctor basic
# ============================================

@test "pwt doctor runs successfully" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt doctor"* ]]
}

@test "pwt doctor checks git" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
    [[ "$output" == *"✓"* ]]
}

@test "pwt doctor checks jq" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"jq"* ]]
}

@test "pwt doctor shows project info" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project"* ]] || [[ "$output" == *"test-project"* ]]
}

@test "pwt doctor shows main app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Main app"* ]] || [[ "$output" == *"$TEST_REPO"* ]]
}

@test "pwt doctor shows worktrees directory" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktrees"* ]] || [[ "$output" == *"worktrees"* ]]
}

# ============================================
# doctor with worktrees
# ============================================

@test "pwt doctor shows worktree count" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DOC1 HEAD
    "$PWT_BIN" create WT-DOC2 HEAD

    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"2"* ]] || [[ "$output" == *"worktree"* ]]
}

# ============================================
# doctor checks Pwtfile
# ============================================

@test "pwt doctor reports Pwtfile when present" {
    cd "$TEST_REPO"
    echo "setup() { echo test; }" > "$TEST_REPO/Pwtfile"

    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pwtfile"* ]]
}

@test "pwt doctor reports Pwtfile not found when absent" {
    cd "$TEST_REPO"
    rm -f "$TEST_REPO/Pwtfile"

    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pwtfile"* ]]
}

# ============================================
# doctor via project prefix
# ============================================

@test "pwt <project> doctor works from anywhere" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt doctor"* ]]
}
