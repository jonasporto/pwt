#!/usr/bin/env bats
# Tests for pwt project and init commands
# Verifies project configuration management

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
  "branch_prefix": "test/",
  "alias": "tp"
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
# project list
# ============================================

@test "pwt project list shows all projects" {
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}

@test "pwt project list shows branch prefix" {
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
    [[ "$output" == *"branch_prefix"* ]]
}

@test "pwt project (no args) defaults to list" {
    run "$PWT_BIN" project
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}

@test "pwt project list shows multiple projects" {
    # Create a second project
    export TEST_REPO2="$TEST_TEMP_DIR/test-repo2"
    mkdir -p "$TEST_REPO2"
    git init -q "$TEST_REPO2"
    cd "$TEST_REPO2"
    git config user.email "test@test.com"
    git config user.name "Test User"
    touch README.md
    git add README.md
    git commit -q -m "Initial commit"

    mkdir -p "$PWT_DIR/projects/second-project"
    cat > "$PWT_DIR/projects/second-project/config.json" << EOF
{
  "path": "$TEST_REPO2",
  "worktrees_dir": "$TEST_TEMP_DIR/worktrees2",
  "branch_prefix": "second/"
}
EOF

    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
    [[ "$output" == *"second-project"* ]]
}

# ============================================
# project show
# ============================================

@test "pwt project show displays project config" {
    run "$PWT_BIN" project show test-project
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}

@test "pwt project show fails without project name" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" project show
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "pwt project show fails for nonexistent project" {
    run "$PWT_BIN" project show nonexistent-project
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Not found"* ]]
}

# ============================================
# project init
# ============================================

@test "pwt project init creates new project" {
    # Create a new repo to init
    local new_repo="$TEST_TEMP_DIR/new-repo"
    mkdir -p "$new_repo"
    git init -q "$new_repo"
    cd "$new_repo"
    git config user.email "test@test.com"
    git config user.name "Test User"
    touch README.md
    git add README.md
    git commit -q -m "Initial"

    run "$PWT_BIN" project init new-project
    [ "$status" -eq 0 ]

    # Verify project was created
    [ -f "$PWT_DIR/projects/new-project/config.json" ]
}

@test "pwt project init requires project name" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" project init
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage"* ]]
}

# ============================================
# project via syntax variations
# ============================================

@test "pwt test-project project show <name> works" {
    # When using project prefix, still need to provide project name for show
    run "$PWT_BIN" test-project project show test-project
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
}

# ============================================
# project alias (single alias per project)
# ============================================

@test "pwt project list shows alias" {
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
    # Should show alias in parentheses
    [[ "$output" == *"tp"* ]]
}

@test "pwt project alias shows current alias" {
    run "$PWT_BIN" project alias test-project
    [ "$status" -eq 0 ]
    [[ "$output" == *"tp"* ]]
}

@test "pwt project alias sets new alias" {
    run "$PWT_BIN" project alias test-project myalias
    [ "$status" -eq 0 ]
    [[ "$output" == *"Set"* ]]

    # Verify alias was set
    run "$PWT_BIN" project alias test-project
    [[ "$output" == "myalias" ]]

    # Restore original
    "$PWT_BIN" project alias test-project tp
}

@test "pwt project alias --clear removes alias" {
    # First set an alias
    "$PWT_BIN" project alias test-project removeme

    run "$PWT_BIN" project alias test-project --clear
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleared"* ]]

    # Verify alias was removed
    run "$PWT_BIN" project alias test-project
    [[ "$output" == "(no alias set)" ]]

    # Restore original
    "$PWT_BIN" project alias test-project tp
}

@test "pwt project alias prevents duplicate alias" {
    # Create a second project with its own alias
    mkdir -p "$PWT_DIR/projects/other-project"
    cat > "$PWT_DIR/projects/other-project/config.json" << EOF
{
  "path": "$TEST_REPO",
  "alias": "otheralias"
}
EOF

    # Try to set same alias on test-project
    run "$PWT_BIN" project alias test-project otheralias
    [ "$status" -ne 0 ]
    [[ "$output" == *"already used"* ]]
}

@test "pwt project alias prevents project name conflict" {
    # Try to set an alias that matches an existing project name
    run "$PWT_BIN" project alias test-project test-project
    [ "$status" -ne 0 ]
    [[ "$output" == *"already a project"* ]]
}

@test "pwt project alias prevents reserved command names" {
    # Try to set an alias that matches a pwt command
    run "$PWT_BIN" project alias test-project list
    [ "$status" -ne 0 ]
    [[ "$output" == *"reserved command"* ]]

    run "$PWT_BIN" project alias test-project create
    [ "$status" -ne 0 ]
    [[ "$output" == *"reserved command"* ]]
}

@test "pwt <alias> resolves to project" {
    cd "$TEST_REPO"

    # Use alias to list - should work and show test-project
    run "$PWT_BIN" tp list
    [ "$status" -eq 0 ]
    # The output should show the project name (test-project) indicating alias resolved
    [[ "$output" == *"test-project"* ]]
}

@test "pwt project alias requires project name" {
    run "$PWT_BIN" project alias
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage"* ]]
}

# ============================================
# pwt alias (shortcut - auto-detects project)
# ============================================

@test "pwt alias shows current project alias" {
    cd "$TEST_REPO"
    run "$PWT_BIN" alias
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-project"* ]]
    [[ "$output" == *"tp"* ]]
}

@test "pwt alias sets new alias" {
    cd "$TEST_REPO"
    run "$PWT_BIN" alias newalias
    [ "$status" -eq 0 ]
    [[ "$output" == *"newalias"* ]]

    # Verify
    run "$PWT_BIN" alias
    [[ "$output" == *"newalias"* ]]

    # Restore
    "$PWT_BIN" alias tp
}

@test "pwt alias --clear removes alias" {
    cd "$TEST_REPO"
    run "$PWT_BIN" alias --clear
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleared"* ]]

    # Verify
    run "$PWT_BIN" alias
    [[ "$output" == *"no alias"* ]]

    # Restore
    "$PWT_BIN" alias tp
}
