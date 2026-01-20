#!/usr/bin/env bats
# Tests for pwt init command
# Verifies project initialization from URL or current directory

load test_helper

setup() {
    setup_test_env

    # Create a bare repo to use as remote
    export BARE_REPO="$TEST_TEMP_DIR/bare-repo.git"
    git init -q --bare "$BARE_REPO"

    # Create a repo with content to push
    export SOURCE_REPO="$TEST_TEMP_DIR/source-repo"
    mkdir -p "$SOURCE_REPO"
    git init -q "$SOURCE_REPO"
    cd "$SOURCE_REPO"
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "content" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"
    git remote add origin "$BARE_REPO"
    git push -q origin master 2>/dev/null || git push -q origin main 2>/dev/null || true
}

teardown() {
    teardown_test_env
}

# ============================================
# init from current directory
# ============================================

@test "pwt init configures current git repo" {
    cd "$TEST_REPO"
    run "$PWT_BIN" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"configured"* ]] || [[ "$output" == *"Config"* ]] || [[ "$output" == *"✓"* ]]
}

@test "pwt init creates project config" {
    cd "$TEST_REPO"
    "$PWT_BIN" init

    # Should create a project config
    local project_name=$(basename "$TEST_REPO")
    [ -d "$PWT_DIR/projects" ]
}

@test "pwt init fails outside git repo" {
    cd "$TEST_TEMP_DIR"
    mkdir -p not-a-repo
    cd not-a-repo

    run "$PWT_BIN" init
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not a git"* ]] || [[ "$output" == *"git"* ]]
}

# ============================================
# init from URL (clone)
# ============================================

@test "pwt init <url> clones repository" {
    cd "$TEST_TEMP_DIR"

    run "$PWT_BIN" init "$BARE_REPO"
    [ "$status" -eq 0 ]

    # Should have cloned the repo
    [ -d "$TEST_TEMP_DIR/bare-repo" ]
}

@test "pwt init <url> configures cloned repo" {
    cd "$TEST_TEMP_DIR"

    "$PWT_BIN" init "$BARE_REPO"

    # Should create project config
    [ -f "$PWT_DIR/projects/bare-repo/config.json" ]
}

@test "pwt init <url> shows usage instructions" {
    cd "$TEST_TEMP_DIR"

    run "$PWT_BIN" init "$BARE_REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"pwt"* ]]
}

@test "pwt init <url> skips if already exists" {
    cd "$TEST_TEMP_DIR"

    # Create directory first
    mkdir -p bare-repo

    run "$PWT_BIN" init "$BARE_REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already exists"* ]] || [[ "$output" == *"exists"* ]]
}

# ============================================
# init sets correct paths
# ============================================

@test "pwt init sets worktrees_dir" {
    cd "$TEST_TEMP_DIR"
    "$PWT_BIN" init "$BARE_REPO"

    local config="$PWT_DIR/projects/bare-repo/config.json"
    [ -f "$config" ]

    local wt_dir=$(jq -r '.worktrees_dir' "$config")
    [ -n "$wt_dir" ]
}

@test "pwt init sets remote in config" {
    cd "$TEST_TEMP_DIR"
    "$PWT_BIN" init "$BARE_REPO"

    local config="$PWT_DIR/projects/bare-repo/config.json"
    local remote=$(jq -r '.remote' "$config")
    [ "$remote" = "$BARE_REPO" ]
}

# ============================================
# init with explicit name (pwt <name> init)
# ============================================

@test "pwt <name> init configures current repo with name" {
    cd "$TEST_REPO"
    run "$PWT_BIN" custom-name init
    [ "$status" -eq 0 ]
    [ -f "$PWT_DIR/projects/custom-name/config.json" ]
    [[ "$output" == *"custom-name"* ]]
}

@test "pwt <name> init <url> clones with specific name" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" my-project init "$BARE_REPO"
    [ "$status" -eq 0 ]
    [ -d "$TEST_TEMP_DIR/my-project" ]
    [ -f "$PWT_DIR/projects/my-project/config.json" ]
}

@test "pwt <name> init <url> sets remote in config" {
    cd "$TEST_TEMP_DIR"
    "$PWT_BIN" named-proj init "$BARE_REPO"

    local config="$PWT_DIR/projects/named-proj/config.json"
    local remote=$(jq -r '.remote' "$config")
    [ "$remote" = "$BARE_REPO" ]
}

@test "pwt <name> init <url> sets correct path in config" {
    cd "$TEST_TEMP_DIR"
    "$PWT_BIN" path-test init "$BARE_REPO"

    local config="$PWT_DIR/projects/path-test/config.json"
    local path=$(jq -r '.path' "$config")
    [ "$path" = "$TEST_TEMP_DIR/path-test" ]
}

@test "pwt <name> init <url> skips if directory exists" {
    cd "$TEST_TEMP_DIR"
    mkdir -p existing-dir

    run "$PWT_BIN" existing-dir init "$BARE_REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already exists"* ]]
}

@test "pwt <name> init fails outside git repo" {
    cd "$TEST_TEMP_DIR"
    mkdir -p not-a-repo
    cd not-a-repo

    run "$PWT_BIN" my-name init
    [ "$status" -ne 0 ]
    [[ "$output" == *"git"* ]]
}

@test "pwt <name> init already configured shows existing config" {
    cd "$TEST_REPO"
    "$PWT_BIN" dup-name init

    run "$PWT_BIN" dup-name init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already configured"* ]]
}
