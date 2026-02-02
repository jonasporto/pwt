#!/usr/bin/env bats
# Tests for shell-init functionality
# Verifies the shell wrapper function works correctly for cd operations

load test_helper

setup() {
    setup_test_env

    # Create worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/test-project-worktrees"
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

    # Create a worktree
    "$PWT_BIN" create TEST-WT HEAD
}

teardown() {
    teardown_test_env
}

# ============================================
# shell-init output
# ============================================

@test "pwt shell-init outputs valid shell function" {
    run "$PWT_BIN" shell-init
    [ "$status" -eq 0 ]
    # Should contain function definition
    [[ "$output" == *"pwt()"* ]] || [[ "$output" == *"function pwt"* ]]
}

@test "pwt shell-init can be sourced without error" {
    # Source the shell-init and verify it doesn't error
    run bash -c "source <($PWT_BIN shell-init) && type pwt | head -1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]] || [[ "$output" == *"pwt is"* ]]
}

# ============================================
# cd via shell function
# ============================================

@test "shell function cd changes directory" {
    cd "$TEST_TEMP_DIR"

    # Source shell-init and test cd
    run bash -c "
        export PWT_DIR='$PWT_DIR'
        source <($PWT_BIN shell-init)
        cd '$TEST_REPO'
        pwt cd TEST-WT
        pwd
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-WT"* ]]
}

@test "shell function cd @ changes to main app" {
    cd "$TEST_TEMP_DIR"

    run bash -c "
        export PWT_DIR='$PWT_DIR'
        source <($PWT_BIN shell-init)
        cd '$TEST_REPO'
        pwt cd @
        pwd
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_REPO"* ]] || [[ "$output" == *"test-repo"* ]]
}

# ============================================
# _cd internal command
# ============================================

@test "pwt _cd returns worktree path" {
    cd "$TEST_REPO"
    # _cd returns the path for cd
    run "$PWT_BIN" _cd TEST-WT
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-WT"* ]]
}

# ============================================
# use via shell function
# ============================================

@test "shell function use updates current symlink" {
    cd "$TEST_REPO"

    run bash -c "
        export PWT_DIR='$PWT_DIR'
        source <($PWT_BIN shell-init)
        pwt use TEST-WT
    "
    [ "$status" -eq 0 ]

    # Verify symlink was created
    [ -L "$PWT_DIR/projects/test-project/current" ]
}

# ============================================
# PWT_WORKTREE env var
# ============================================

@test "shell function sets PWT_WORKTREE after cd" {
    run bash -c "
        export PWT_DIR='$PWT_DIR'
        source <($PWT_BIN shell-init)
        cd '$TEST_REPO'
        pwt cd TEST-WT
        echo \"\$PWT_WORKTREE\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-WT"* ]]
}

# ============================================
# Pass-through to binary
# ============================================

@test "shell function passes non-cd commands to binary" {
    cd "$TEST_REPO"

    run bash -c "
        export PWT_DIR='$PWT_DIR'
        source <($PWT_BIN shell-init)
        pwt list --porcelain
    "
    [ "$status" -eq 0 ]
    # Should be valid JSON
    echo "$output" | jq . > /dev/null 2>&1
    [ "$?" -eq 0 ]
}

@test "shell function passes help command correctly" {
    run bash -c "
        export PWT_DIR='$PWT_DIR'
        source <($PWT_BIN shell-init)
        pwt help
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"pwt"* ]]
}

# ============================================
# Previous worktree navigation (pwt -)
# ============================================

@test "pwt cd - fails when no previous" {
    cd "$TEST_REPO"
    # Clear any previous state
    rm -f "$PWT_DIR/projects/test-project/previous"

    run "$PWT_BIN" _cd -
    [ "$status" -ne 0 ]
    [[ "$output" == *"No previous"* ]]
}

@test "pwt cd - returns to previous worktree" {
    cd "$TEST_REPO"
    # Create second worktree
    "$PWT_BIN" create TEST-WT2 HEAD

    # Navigate: WT -> WT2 -> - (should go back to WT)
    "$PWT_BIN" _cd TEST-WT
    "$PWT_BIN" _cd TEST-WT2

    run "$PWT_BIN" _cd -
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-WT"* ]]
    # Should NOT contain TEST-WT2
    [[ "$output" != *"TEST-WT2"* ]]
}

@test "pwt cd - toggles between two worktrees" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-TOGGLE HEAD

    # Navigate between two worktrees
    "$PWT_BIN" _cd TEST-WT
    "$PWT_BIN" _cd TEST-TOGGLE

    # First - should go to TEST-WT
    run "$PWT_BIN" _cd -
    [[ "$output" == *"TEST-WT"* ]]

    # Second - should go back to TEST-TOGGLE
    run "$PWT_BIN" _cd -
    [[ "$output" == *"TEST-TOGGLE"* ]]
}

@test "pwt cd - works with main app (@)" {
    cd "$TEST_REPO"

    # Navigate: @ -> WT -> - (should go back to @)
    "$PWT_BIN" _cd @
    "$PWT_BIN" _cd TEST-WT

    run "$PWT_BIN" _cd -
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_REPO"* ]] || [[ "$output" == *"test-repo"* ]]
}

@test "pwt - is shortcut for pwt cd -" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-SHORT HEAD

    "$PWT_BIN" _cd TEST-WT
    "$PWT_BIN" _cd TEST-SHORT

    run "$PWT_BIN" -
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-WT"* ]]
}
