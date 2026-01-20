#!/usr/bin/env bats
# Tests for project detection and resolution
# Verifies pwt correctly identifies projects from various contexts

load test_helper

setup() {
    setup_test_env

    # Create worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create main project config
    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/",
  "aliases": ["tp", "test"]
}
EOF

    # Create a second project for multi-project tests
    export TEST_REPO2="$TEST_TEMP_DIR/test-repo2"
    export TEST_WORKTREES2="$TEST_TEMP_DIR/worktrees2"
    mkdir -p "$TEST_REPO2" "$TEST_WORKTREES2"
    git init -q "$TEST_REPO2"
    cd "$TEST_REPO2"
    git config user.email "test@test.com"
    git config user.name "Test User"
    touch README.md
    git add README.md
    git commit -q -m "Initial commit"

    mkdir -p "$PWT_DIR/projects/other-project"
    cat > "$PWT_DIR/projects/other-project/config.json" << EOF
{
  "path": "$TEST_REPO2",
  "worktrees_dir": "$TEST_WORKTREES2",
  "branch_prefix": "other/",
  "aliases": ["op"]
}
EOF
}

teardown() {
    teardown_test_env
}

# ============================================
# Project detection from current directory
# ============================================

@test "pwt detects project from main repo directory" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --porcelain
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "test-project" ]
}

@test "pwt detects project from worktree directory" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DETECT HEAD

    cd "$TEST_WORKTREES/WT-DETECT"
    run "$PWT_BIN" list --porcelain
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "test-project" ]
}

@test "pwt detects second project from its directory" {
    cd "$TEST_REPO2"
    run "$PWT_BIN" list --porcelain
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "other-project" ]
}

# ============================================
# Project resolution by name
# ============================================

@test "pwt resolves project by full name" {
    cd "$TEST_TEMP_DIR"  # Outside any project
    run "$PWT_BIN" test-project list --porcelain
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "test-project" ]
}

@test "pwt resolves project by alias" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" tp list --porcelain
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "test-project" ]
}

@test "pwt resolves second alias" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test list --porcelain
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "test-project" ]
}

@test "pwt resolves other project by alias" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" op list --porcelain
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "other-project" ]
}

# ============================================
# Project not found errors
# ============================================

@test "pwt shows error for unknown project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" nonexistent-project list
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"No project"* ]]
}

@test "pwt shows error when no project detected and not specified" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" list
    [ "$status" -ne 0 ]
    [[ "$output" == *"project"* ]]
}

# ============================================
# Multi-project operations
# ============================================

@test "pwt operates on correct project when switching between projects" {
    # Create worktree in first project
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PROJ1 HEAD

    # Create worktree in second project
    cd "$TEST_REPO2"
    "$PWT_BIN" create WT-PROJ2 HEAD

    # Verify each project only sees its own worktrees
    cd "$TEST_REPO"
    run "$PWT_BIN" list
    [[ "$output" == *"WT-PROJ1"* ]]
    [[ "$output" != *"WT-PROJ2"* ]]

    cd "$TEST_REPO2"
    run "$PWT_BIN" list
    [[ "$output" == *"WT-PROJ2"* ]]
    [[ "$output" != *"WT-PROJ1"* ]]
}

@test "pwt can access both projects using explicit names from neutral directory" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-A HEAD

    cd "$TEST_REPO2"
    "$PWT_BIN" create WT-B HEAD

    # From neutral directory, access both
    cd "$TEST_TEMP_DIR"

    run "$PWT_BIN" test-project list
    [[ "$output" == *"WT-A"* ]]

    run "$PWT_BIN" other-project list
    [[ "$output" == *"WT-B"* ]]
}

# ============================================
# Project config reading
# ============================================

@test "pwt uses worktrees_dir from config" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-CONFIG HEAD

    # Verify worktree was created in configured directory
    [ -d "$TEST_WORKTREES/WT-CONFIG" ]
}

@test "pwt uses branch_prefix from config" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PREFIX HEAD

    # Verify branch has configured prefix
    cd "$TEST_WORKTREES/WT-PREFIX"
    local branch=$(git branch --show-current)
    [[ "$branch" == "test/"* ]]
}

@test "pwt uses different prefix for different project" {
    cd "$TEST_REPO2"
    "$PWT_BIN" create WT-OTHER HEAD

    # Verify branch has other project's prefix
    cd "$TEST_WORKTREES2/WT-OTHER"
    local branch=$(git branch --show-current)
    [[ "$branch" == "other/"* ]]
}
