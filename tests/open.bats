#!/usr/bin/env bats
# Tests for pwt open command
# Verifies opening worktrees in Finder

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

    # Mock the 'open' command to avoid actually opening Finder
    export PATH="$TEST_TEMP_DIR/bin:$PATH"
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/open" << 'EOF'
#!/bin/bash
echo "MOCK_OPEN: $1"
EOF
    chmod +x "$TEST_TEMP_DIR/bin/open"
}

teardown() {
    teardown_test_env
}

# ============================================
# open basic
# ============================================

@test "pwt open opens worktree directory" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-OPEN HEAD

    run "$PWT_BIN" open WT-OPEN
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-OPEN"* ]]
}

@test "pwt open @ opens main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" open @
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_REPO"* ]] || [[ "$output" == *"Opening"* ]]
}

@test "pwt open without arg opens main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" open
    [ "$status" -eq 0 ]
}

# ============================================
# open errors
# ============================================

@test "pwt open fails for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" open NONEXISTENT
    [ "$status" -ne 0 ]
}

# ============================================
# open via project prefix
# ============================================

@test "pwt <project> open works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project open WT-REMOTE
    [ "$status" -eq 0 ]
}
