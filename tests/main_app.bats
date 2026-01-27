#!/usr/bin/env bats
# Tests for main app (@) handling
# Verifies that @ works as a worktree for applicable commands

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
# pwt info from main app
# ============================================

@test "pwt info works from main app directory" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info
    [ "$status" -eq 0 ]
    [[ "$output" == *"@"* ]]
    [[ "$output" == *"Ticket"* ]] || [[ "$output" == *"Branch"* ]]
}

@test "pwt info @ works with explicit name" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info @
    [ "$status" -eq 0 ]
    [[ "$output" == *"@"* ]]
}

@test "pwt info shows main app branch" {
    cd "$TEST_REPO"
    local current_branch=$(git branch --show-current)
    run "$PWT_BIN" info
    [ "$status" -eq 0 ]
    [[ "$output" == *"$current_branch"* ]]
}

@test "pwt info shows Path for main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info @
    [ "$status" -eq 0 ]
    [[ "$output" == *"Path"* ]]
    [[ "$output" == *"$TEST_REPO"* ]]
}

# ============================================
# pwt (no args) in project
# ============================================

@test "pwt with no args shows list when inside project" {
    cd "$TEST_REPO"
    run "$PWT_BIN"
    [ "$status" -eq 0 ]
    # Should show list output (header with columns)
    [[ "$output" == *"Worktree"* ]] || [[ "$output" == *"Branch"* ]] || [[ "$output" == *"@"* ]]
}

@test "pwt shows help when outside any project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN"
    # Should show help/usage
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"Commands"* ]] || [[ "$output" == *"pwt"* ]]
}

# ============================================
# pwt current from main app
# ============================================

@test "pwt current --name returns @ from main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" current --name
    [ "$status" -eq 0 ]
    [ "$output" = "@" ]
}

@test "pwt current --path returns main app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" current --path --resolved
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt current --branch returns main branch" {
    cd "$TEST_REPO"
    local expected_branch=$(git branch --show-current)
    run "$PWT_BIN" current --branch
    [ "$status" -eq 0 ]
    [ "$output" = "$expected_branch" ]
}

@test "pwt current --json returns valid JSON for main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" current --json
    [ "$status" -eq 0 ]
    echo "$output" | jq . > /dev/null 2>&1
    [ "$?" -eq 0 ]
    [[ "$output" == *'"in_worktree"'* ]] || [[ "$output" == *"@"* ]]
}

# ============================================
# pwt remove @ is blocked
# ============================================

@test "pwt remove @ shows error and is blocked" {
    cd "$TEST_REPO"
    run "$PWT_BIN" remove @ -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot remove"* ]]
    [[ "$output" == *"main"* ]]
}

@test "pwt remove @ from inside main app is blocked" {
    cd "$TEST_REPO"
    export PWT_WORKTREE="@"
    run "$PWT_BIN" remove -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot remove"* ]] || [[ "$output" == *"Not in a worktree"* ]]
}

@test "main app still exists after blocked remove attempt" {
    cd "$TEST_REPO"
    "$PWT_BIN" remove @ -y 2>/dev/null || true
    [ -d "$TEST_REPO" ]
    [ -d "$TEST_REPO/.git" ]
}

# ============================================
# pwt cd @
# ============================================

@test "pwt cd @ outputs main app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd @
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt cd @/ handles trailing slash" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd "@/"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt cd @ works from worktree" {
    cd "$TEST_REPO"
    # Create a worktree
    git branch test/wt-one
    mkdir -p "$TEST_WORKTREES/wt-one"
    git worktree add "$TEST_WORKTREES/wt-one" test/wt-one 2>/dev/null || true

    cd "$TEST_WORKTREES/wt-one"
    run "$PWT_BIN" cd @
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

# ============================================
# pwt run @
# ============================================

@test "pwt run @ executes command in main app" {
    cd "$TEST_TEMP_DIR"  # Outside main app
    run "$PWT_BIN" --project test-project run @ pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_REPO"* ]]
}

@test "pwt run @ git status works" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run @ git status
    [ "$status" -eq 0 ]
    [[ "$output" == *"branch"* ]] || [[ "$output" == *"commit"* ]]
}

# ============================================
# pwt list shows main app
# ============================================

@test "pwt list includes @ for main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"@"* ]]
}

@test "pwt list --names includes @/" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --names
    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
}

# ============================================
# Project prefix with main app
# ============================================

@test "pwt <project> cd @ works from outside project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project cd @
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

@test "pwt <project> info @ works from outside project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project info @
    [ "$status" -eq 0 ]
    [[ "$output" == *"@"* ]]
}

@test "pwt <project> without command outputs main path" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO" ]
}

# ============================================
# Main app in deep subdirectory
# ============================================

@test "pwt info works from subdirectory of main app" {
    cd "$TEST_REPO"
    mkdir -p subdir/deep
    cd subdir/deep
    run "$PWT_BIN" info
    [ "$status" -eq 0 ]
    [[ "$output" == *"@"* ]]
}

@test "pwt current --name returns @ from subdirectory" {
    cd "$TEST_REPO"
    mkdir -p subdir/deep
    cd subdir/deep
    run "$PWT_BIN" current --name
    [ "$status" -eq 0 ]
    [ "$output" = "@" ]
}

# ============================================
# Edge cases
# ============================================

@test "@ is not confused with actual worktree named @" {
    cd "$TEST_REPO"
    # Attempt to create a worktree literally named @ (should fail or be weird)
    # Just verify our @ handling doesn't break
    run "$PWT_BIN" info @
    [ "$status" -eq 0 ]
    [[ "$output" == *"Path"* ]]
    [[ "$output" == *"$TEST_REPO"* ]]
}

@test "pwt info @ shows different data than regular worktree" {
    cd "$TEST_REPO"
    # Create a worktree
    "$PWT_BIN" create TEST-COMPARE HEAD

    # Compare info outputs
    run "$PWT_BIN" info @
    local main_info="$output"

    run "$PWT_BIN" info TEST-COMPARE
    local wt_info="$output"

    # Should be different (different paths at minimum)
    [ "$main_info" != "$wt_info" ]
}
