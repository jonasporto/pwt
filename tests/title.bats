#!/usr/bin/env bats
# Tests for pwt terminal title feature
# Verifies title format, placeholders, and configuration

load test_helper

setup() {
    setup_test_env

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES"
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
# shell-init includes title functions
# ============================================

@test "shell-init (bash) includes _pwt_update_title function" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"_pwt_update_title()"* ]]
}

@test "shell-init (bash) includes _pwt_detect_project function" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"_pwt_detect_project()"* ]]
}

@test "shell-init (bash) includes chpwd/PROMPT_COMMAND hook" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROMPT_COMMAND"* ]] || [[ "$output" == *"chpwd"* ]]
}

@test "shell-init (zsh) includes chpwd hook" {
    run "$PWT_BIN" shell-init zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"chpwd"* ]]
}

@test "shell-init (fish) includes _pwt_update_title function" {
    run "$PWT_BIN" shell-init fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"function _pwt_update_title"* ]]
}

@test "shell-init (fish) includes _pwt_detect_project function" {
    run "$PWT_BIN" shell-init fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"function _pwt_detect_project"* ]]
}

@test "shell-init (fish) uses --on-variable PWD hook" {
    run "$PWT_BIN" shell-init fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"--on-variable PWD"* ]]
}

# ============================================
# format placeholders
# ============================================

@test "shell-init includes {project} placeholder handling" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"{project}"* ]]
}

@test "shell-init includes {worktree} placeholder handling" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"{worktree}"* ]]
}

@test "shell-init includes {branch} placeholder handling" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"{branch}"* ]]
}

@test "shell-init includes {path} placeholder handling" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    # Check for path replacement line (escaped in heredoc)
    [[ "$output" == *'\{path'* ]]
}

@test "shell-init includes {dir} placeholder handling" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    # Check for dir replacement line (escaped in heredoc)
    [[ "$output" == *'\{dir'* ]]
}

# ============================================
# config support
# ============================================

@test "shell-init checks PWT_TITLE_ENABLED" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWT_TITLE_ENABLED"* ]]
}

@test "shell-init checks PWT_TITLE_FORMAT" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWT_TITLE_FORMAT"* ]]
}

@test "shell-init reads config.json title.format" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"title.format"* ]]
}

@test "shell-init reads config.json title.enabled" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"title.enabled"* ]]
}

# ============================================
# default format
# ============================================

@test "shell-init has default format {project}:{worktree}" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *'{project}:{worktree}'* ]]
}

# ============================================
# PWT_PROJECT export
# ============================================

@test "shell-init exports PWT_PROJECT" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWT_PROJECT"* ]]
}

@test "shell-init exports PWT_WORKTREE" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWT_WORKTREE"* ]]
}

# ============================================
# title escape sequence
# ============================================

@test "shell-init uses correct terminal title escape sequence" {
    run "$PWT_BIN" shell-init bash
    [ "$status" -eq 0 ]
    # Check for OSC escape sequence: \033]0;...\007
    [[ "$output" == *"033]0;"* ]]
}
