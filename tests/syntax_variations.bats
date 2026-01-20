#!/usr/bin/env bats
# Tests for pwt command syntax variations
# Verifies both "pwt command" and "pwt project command" work from anywhere

load test_helper

setup() {
    setup_test_env

    # Create a worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create project config with alias
    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/",
  "aliases": ["tp"]
}
EOF

    # Create a worktree for testing
    export TEST_WORKTREE="$TEST_WORKTREES/TEST-1234"
    git -C "$TEST_REPO" worktree add -q "$TEST_WORKTREE" -b test/TEST-1234

    # Create current symlink
    mkdir -p "$PWT_DIR/projects/test-project"
    ln -sfn "$TEST_WORKTREE" "$PWT_DIR/projects/test-project/current"

    # Create an unrelated directory (to test "from anywhere")
    export UNRELATED_DIR="$TEST_TEMP_DIR/unrelated"
    mkdir -p "$UNRELATED_DIR"
}

teardown() {
    teardown_test_env
}

# ============================================
# pwt list - both syntaxes
# ============================================

@test "pwt list works from project directory" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

@test "pwt <project> list works from anywhere" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" test-project list
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

@test "pwt <alias> list works from anywhere" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" tp list
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

# ============================================
# pwt cd - both syntaxes
# ============================================

@test "pwt cd <worktree> outputs path from project directory" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd TEST-1234
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_WORKTREE"* ]]
}

@test "pwt <project> cd <worktree> outputs path from anywhere" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" test-project cd TEST-1234
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_WORKTREE"* ]]
}

@test "pwt cd current outputs symlink path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd current
    [ "$status" -eq 0 ]
    [[ "$output" == *"/current"* ]]
}

@test "pwt <project> cd current outputs symlink path from anywhere" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" test-project cd current
    [ "$status" -eq 0 ]
    [[ "$output" == *"/current"* ]]
}

@test "pwt cd @ outputs main app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd @
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_REPO"* ]]
}

# ============================================
# pwt use - both syntaxes
# ============================================

@test "pwt use <worktree> updates current symlink" {
    cd "$TEST_REPO"
    run "$PWT_BIN" use TEST-1234
    [ "$status" -eq 0 ]

    # Verify symlink was updated
    local target=$(readlink "$PWT_DIR/projects/test-project/current")
    [[ "$target" == *"TEST-1234"* ]]
}

@test "pwt <project> use <worktree> works from anywhere" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" test-project use TEST-1234
    [ "$status" -eq 0 ]

    # Verify symlink was updated
    local target=$(readlink "$PWT_DIR/projects/test-project/current")
    [[ "$target" == *"TEST-1234"* ]]
}

@test "pwt use @ points to main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" use @
    [ "$status" -eq 0 ]

    # Verify symlink points to main app
    local target=$(readlink "$PWT_DIR/projects/test-project/current")
    [[ "$target" == "$TEST_REPO" ]]
}

@test "pwt use with partial match finds worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" use 1234
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

# ============================================
# pwt current - both syntaxes
# ============================================

@test "pwt current outputs symlink path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" current
    [ "$status" -eq 0 ]
    [[ "$output" == *"/current"* ]]
}

@test "pwt current --resolved outputs target path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" current --resolved
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

@test "pwt <project> current works from anywhere" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" test-project current
    [ "$status" -eq 0 ]
    [[ "$output" == *"/current"* ]]
}

# ============================================
# pwt info - both syntaxes
# ============================================

@test "pwt info <worktree> shows details" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info TEST-1234
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

@test "pwt <project> info <worktree> works from anywhere" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" test-project info TEST-1234
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

# ============================================
# Branch name matching in pwt use
# ============================================

@test "pwt use matches by branch name with slash" {
    cd "$TEST_REPO"
    # The worktree has branch test/TEST-1234
    run "$PWT_BIN" use test/TEST-1234
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-1234"* ]]
}

@test "pwt use matches by partial branch name" {
    cd "$TEST_REPO"
    run "$PWT_BIN" use TEST-1234
    [ "$status" -eq 0 ]
}

# ============================================
# Error cases
# ============================================

@test "pwt cd nonexistent worktree shows error" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd nonexistent-worktree
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"No worktree"* ]]
}

@test "pwt use nonexistent worktree shows error" {
    cd "$TEST_REPO"
    run "$PWT_BIN" use nonexistent-worktree
    [ "$status" -ne 0 ]
}

@test "pwt <unknown-project> list shows error" {
    cd "$UNRELATED_DIR"
    run "$PWT_BIN" unknown-project list
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"No project"* ]]
}
