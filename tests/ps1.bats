#!/usr/bin/env bats
# Tests for pwt ps1 command
# Fast prompt helper for shell prompts, tmux, etc.

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
# ps1 without current symlink
# ============================================

@test "pwt ps1 outputs nothing when no current symlink" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ============================================
# ps1 with current symlink
# ============================================

@test "pwt ps1 outputs pwt@NAME when current is set" {
    cd "$TEST_REPO"

    # Create a worktree
    run "$PWT_BIN" create feature-123 HEAD
    [ "$status" -eq 0 ]

    # Set it as current
    run "$PWT_BIN" use feature-123
    [ "$status" -eq 0 ]

    # Check ps1 output
    run "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ "$output" = "pwt@feature-123" ]
}

@test "pwt ps1 works with different worktree names" {
    cd "$TEST_REPO"

    # Create and use a worktree with different name pattern
    run "$PWT_BIN" create JIRA-456 HEAD
    [ "$status" -eq 0 ]

    run "$PWT_BIN" use JIRA-456
    [ "$status" -eq 0 ]

    run "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ "$output" = "pwt@JIRA-456" ]
}

# ============================================
# ps1 mismatch detection
# ============================================

@test "pwt ps1 adds ! when pwd is in different worktree" {
    cd "$TEST_REPO"

    # Create two worktrees
    run "$PWT_BIN" create feature-A HEAD
    [ "$status" -eq 0 ]

    run "$PWT_BIN" create feature-B HEAD
    [ "$status" -eq 0 ]

    # Set feature-A as current
    run "$PWT_BIN" use feature-A
    [ "$status" -eq 0 ]

    # But cd into feature-B
    cd "$TEST_WORKTREES/feature-B"

    # ps1 should show mismatch
    run "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ "$output" = "pwt@feature-A!" ]
}

@test "pwt ps1 no mismatch when pwd matches current" {
    cd "$TEST_REPO"

    # Create worktree
    run "$PWT_BIN" create feature-X HEAD
    [ "$status" -eq 0 ]

    # Set as current
    run "$PWT_BIN" use feature-X
    [ "$status" -eq 0 ]

    # cd into same worktree
    cd "$TEST_WORKTREES/feature-X"

    # No mismatch
    run "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ "$output" = "pwt@feature-X" ]
}

@test "pwt ps1 no mismatch when pwd is outside worktrees dir" {
    cd "$TEST_REPO"

    # Create and use worktree
    run "$PWT_BIN" create feature-Y HEAD
    [ "$status" -eq 0 ]

    run "$PWT_BIN" use feature-Y
    [ "$status" -eq 0 ]

    # Stay in main repo (outside worktrees dir)
    cd "$TEST_REPO"

    # No mismatch since we're not in worktrees dir
    run "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ "$output" = "pwt@feature-Y" ]
}

# ============================================
# ps1 with project prefix
# ============================================

@test "pwt <project> ps1 works with explicit project" {
    cd "$TEST_TEMP_DIR"  # outside project

    # Create worktree from main repo
    cd "$TEST_REPO"
    run "$PWT_BIN" create feature-Z HEAD
    [ "$status" -eq 0 ]

    run "$PWT_BIN" use feature-Z
    [ "$status" -eq 0 ]

    # Go outside project and use project prefix
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project ps1
    [ "$status" -eq 0 ]
    [ "$output" = "pwt@feature-Z" ]
}

# ============================================
# ps1 edge cases
# ============================================

@test "pwt ps1 handles broken symlink gracefully" {
    cd "$TEST_REPO"

    # Create a worktree and set as current
    run "$PWT_BIN" create temp-wt HEAD
    [ "$status" -eq 0 ]

    run "$PWT_BIN" use temp-wt
    [ "$status" -eq 0 ]

    # Manually break the symlink by removing the target
    rm -rf "$TEST_WORKTREES/temp-wt"

    # ps1 should handle gracefully (no output)
    run "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pwt ps1 is fast (no git operations)" {
    cd "$TEST_REPO"

    # Create and use worktree
    run "$PWT_BIN" create perf-test HEAD
    [ "$status" -eq 0 ]

    run "$PWT_BIN" use perf-test
    [ "$status" -eq 0 ]

    # Time the ps1 command - should be very fast
    # We just verify it completes quickly (under 1 second)
    run timeout 1 "$PWT_BIN" ps1
    [ "$status" -eq 0 ]
    [ "$output" = "pwt@perf-test" ]
}
