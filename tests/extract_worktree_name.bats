#!/usr/bin/env bats
# Tests for extract_worktree_name function

load test_helper

setup() {
    # Source the extract_worktree_name function from pwt
    source_pwt_function extract_worktree_name
}

@test "extracts simple branch name unchanged" {
    run extract_worktree_name "my-feature"
    [ "$status" -eq 0 ]
    [ "$output" = "my-feature" ]
}

@test "strips 'feature/' prefix" {
    run extract_worktree_name "feature/my-feature"
    [ "$status" -eq 0 ]
    [ "$output" = "my-feature" ]
}

@test "strips 'user/' prefix (like jp/)" {
    run extract_worktree_name "jp/TICKET-123-fix-bug"
    [ "$status" -eq 0 ]
    [ "$output" = "TICKET-123-fix-bug" ]
}

@test "strips 'bugfix/' prefix" {
    run extract_worktree_name "bugfix/fix_something"
    [ "$status" -eq 0 ]
    [ "$output" = "fix_something" ]
}

@test "strips 'hotfix/' prefix" {
    run extract_worktree_name "hotfix/urgent-fix"
    [ "$status" -eq 0 ]
    [ "$output" = "urgent-fix" ]
}

@test "strips multiple path segments" {
    run extract_worktree_name "user/feature/TICKET-123"
    [ "$status" -eq 0 ]
    [ "$output" = "TICKET-123" ]
}

@test "handles branch with only slashes" {
    run extract_worktree_name "a/b/c/d/e"
    [ "$status" -eq 0 ]
    [ "$output" = "e" ]
}

@test "preserves ticket format with dashes" {
    run extract_worktree_name "feature/TICKET-12345-some-description"
    [ "$status" -eq 0 ]
    [ "$output" = "TICKET-12345-some-description" ]
}

@test "handles empty input" {
    run extract_worktree_name ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "handles input with no prefix" {
    run extract_worktree_name "simple"
    [ "$status" -eq 0 ]
    [ "$output" = "simple" ]
}
