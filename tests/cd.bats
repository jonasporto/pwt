#!/usr/bin/env bats
# Tests for pwt cd command and completion

load test_helper

setup() {
    setup_test_env

    cd "$TEST_REPO"

    # Create worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-repo"
    cat > "$PWT_DIR/projects/test-repo/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/",
  "alias": "tr"
}
EOF

    # Create a couple of worktrees for testing
    git branch test/wt-one 2>/dev/null || true
    git branch test/wt-two 2>/dev/null || true
    mkdir -p "$TEST_WORKTREES/wt-one"
    mkdir -p "$TEST_WORKTREES/wt-two"
    git worktree add "$TEST_WORKTREES/wt-one" test/wt-one 2>/dev/null || true
    git worktree add "$TEST_WORKTREES/wt-two" test/wt-two 2>/dev/null || true
}

teardown() {
    teardown_test_env
}

# ============================================
# Basic cd navigation tests
# ============================================

@test "pwt cd @ outputs main app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd @

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt cd @/ outputs main app path (trailing slash from completion)" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd @/

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt cd <worktree> outputs worktree path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd wt-one

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

@test "pwt cd <worktree>/ outputs worktree path (trailing slash from completion)" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd wt-one/

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

@test "pwt cd with no args outputs main if no last-used" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt cd - returns error when no previous worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd -

    [ "$status" -ne 0 ]
    [[ "$output" == *"No previous"* ]]
}

@test "pwt cd shows error for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd nonexistent

    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"No matches"* ]]
}

# ============================================
# cd from inside worktree
# ============================================

@test "pwt cd @ works from inside a worktree" {
    cd "$TEST_WORKTREES/wt-one"
    run "$PWT_BIN" cd @

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt cd <other-worktree> works from inside a worktree" {
    cd "$TEST_WORKTREES/wt-one"
    run "$PWT_BIN" cd wt-two

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-two" ]
}

@test "pwt cd with partial match works" {
    cd "$TEST_REPO"
    # "one" should match "wt-one"
    run "$PWT_BIN" cd one

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

# ============================================
# cd with project specified (pwt <project> cd)
# ============================================

@test "pwt <project> cd @ works from outside project" {
    cd "$HOME"
    run "$PWT_BIN" test-repo cd @

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt <project> cd <worktree> works from outside project" {
    cd "$HOME"
    run "$PWT_BIN" test-repo cd wt-one

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

@test "pwt <alias> cd @ works from outside project" {
    cd "$HOME"
    run "$PWT_BIN" tr cd @

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt <alias> cd <worktree> works from outside project" {
    cd "$HOME"
    run "$PWT_BIN" tr cd wt-two

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-two" ]
}

@test "pwt <alias> cd <worktree>/ works with trailing slash" {
    cd "$HOME"
    run "$PWT_BIN" tr cd wt-two/

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-two" ]
}

@test "pwt --project <name> cd works" {
    cd "$HOME"
    run "$PWT_BIN" --project test-repo cd wt-one

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

@test "pwt --project <alias> cd works" {
    cd "$HOME"
    run "$PWT_BIN" --project tr cd wt-one

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

# ============================================
# cd with different project context
# ============================================

@test "pwt <project> cd works when inside different project" {
    # Create a second project
    local other_repo="$TEST_TEMP_DIR/other-repo"
    mkdir -p "$other_repo"
    git init -q "$other_repo"
    cd "$other_repo"
    git config user.email "test@test.com"
    git config user.name "Test User"
    touch README.md
    git add README.md
    git commit -q -m "Initial commit"

    mkdir -p "$PWT_DIR/projects/other-repo"
    cat > "$PWT_DIR/projects/other-repo/config.json" << EOF
{
  "path": "$other_repo",
  "worktrees_dir": "$TEST_TEMP_DIR/other-worktrees",
  "branch_prefix": "feat/"
}
EOF

    # From inside other-repo, cd to test-repo's worktree
    cd "$other_repo"
    run "$PWT_BIN" test-repo cd wt-one

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

# ============================================
# cd --help
# ============================================

@test "pwt cd --help shows usage" {
    run "$PWT_BIN" cd --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"worktree"* ]]
}

@test "pwt cd -h shows usage" {
    run "$PWT_BIN" cd -h

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ============================================
# Completion integration tests
# These test that list --names provides correct data for completion
# ============================================

@test "completion: list --names from main shows all worktrees" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"wt-one/"* ]]
    [[ "$output" == *"wt-two/"* ]]
}

@test "completion: list --names from inside worktree shows all worktrees" {
    cd "$TEST_WORKTREES/wt-one"
    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"wt-one/"* ]]
    [[ "$output" == *"wt-two/"* ]]
}

@test "completion: pwt <project> list --names from outside project" {
    cd "$HOME"
    run "$PWT_BIN" test-repo list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"wt-one/"* ]]
    [[ "$output" == *"wt-two/"* ]]
}

@test "completion: pwt <alias> list --names from outside project" {
    cd "$HOME"
    run "$PWT_BIN" tr list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"wt-one/"* ]]
    [[ "$output" == *"wt-two/"* ]]
}

@test "completion: --project flag list --names from outside project" {
    cd "$HOME"
    run "$PWT_BIN" --project tr list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"wt-one/"* ]]
    [[ "$output" == *"wt-two/"* ]]
}

# ============================================
# Edge cases
# ============================================

@test "pwt cd handles worktree with special characters in name" {
    cd "$TEST_REPO"

    # Create worktree with hyphen and numbers (common ticket format)
    git branch test/TICKET-12345 2>/dev/null || true
    mkdir -p "$TEST_WORKTREES/TICKET-12345"
    git worktree add "$TEST_WORKTREES/TICKET-12345" test/TICKET-12345 2>/dev/null || true

    run "$PWT_BIN" cd TICKET-12345

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/TICKET-12345" ]
}

@test "pwt cd handles worktree with trailing slash in name gracefully" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd "wt-one/"

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_WORKTREES/wt-one" ]
}

# ============================================
# pwt <project> without command = cd @
# ============================================

@test "pwt <project> without command outputs main app path" {
    cd "$HOME"
    run "$PWT_BIN" test-repo

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt <alias> without command outputs main app path" {
    cd "$HOME"
    run "$PWT_BIN" tr

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt <project> --help shows help" {
    cd "$HOME"
    run "$PWT_BIN" test-repo --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Power Worktrees"* ]]
    [[ "$output" == *"Commands"* ]]
}

@test "pwt <project> -h shows help" {
    cd "$HOME"
    run "$PWT_BIN" test-repo -h

    [ "$status" -eq 0 ]
    [[ "$output" == *"Power Worktrees"* ]]
}
