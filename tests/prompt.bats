#!/usr/bin/env bats
# Tests for pwt prompt command
# Verifies shell prompt snippets

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
# prompt zsh
# ============================================

@test "pwt prompt outputs zsh snippet by default" {
    run "$PWT_BIN" prompt
    [ "$status" -eq 0 ]
    [[ "$output" == *"zsh"* ]] || [[ "$output" == *"PROMPT"* ]]
}

@test "pwt prompt zsh outputs zsh integration" {
    run "$PWT_BIN" prompt zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"zsh"* ]] || [[ "$output" == *"PROMPT"* ]]
}

# ============================================
# prompt bash
# ============================================

@test "pwt prompt bash outputs bash integration" {
    run "$PWT_BIN" prompt bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"bash"* ]] || [[ "$output" == *"PS1"* ]]
}

# ============================================
# prompt starship
# ============================================

@test "pwt prompt starship outputs starship config" {
    run "$PWT_BIN" prompt starship
    [ "$status" -eq 0 ]
    [[ "$output" == *"starship"* ]] || [[ "$output" == *"custom"* ]] || [[ "$output" == *"toml"* ]]
}

# ============================================
# prompt content
# ============================================

@test "pwt prompt contains PWT_WORKTREE reference" {
    run "$PWT_BIN" prompt
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWT_WORKTREE"* ]]
}

@test "pwt prompt is valid shell code" {
    # Should be sourceable without syntax errors
    run bash -c "source <($PWT_BIN prompt bash) 2>&1 || echo SYNTAX_ERROR"
    [[ "$output" != *"SYNTAX_ERROR"* ]] || [[ "$output" != *"syntax error"* ]]
}
