#!/usr/bin/env bats
# Tests for shell completions - ensures completions stay in sync with commands

load test_helper

# ============================================
# Completions files exist
# ============================================

@test "zsh completions file exists" {
    [ -f "$PWD_DIR/completions/_pwt" ]
}

@test "bash completions file exists" {
    [ -f "$PWD_DIR/completions/pwt.bash" ]
}

@test "fish completions file exists" {
    [ -f "$PWD_DIR/completions/pwt.fish" ]
}

# ============================================
# All commands have zsh completions
# ============================================

@test "zsh completions include all main commands" {
    local completions_file="$PWD_DIR/completions/_pwt"

    # Commands that should be in completions
    local commands=(
        "init"
        "create"
        "add"
        "list"
        "ls"
        "tree"
        "status"
        "cd"
        "use"
        "current"
        "info"
        "show"
        "remove"
        "rm"
        "server"
        "repair"
        "fix"
        "auto-remove"
        "cleanup"
        "restore"
        "fix-port"
        "run"
        "for-each"
        "shell"
        "editor"
        "ai"
        "open"
        "diff"
        "copy"
        "pick"
        "select"
        "doctor"
        "meta"
        "project"
        "config"
        "port"
        "plugin"
        "claude-setup"
        "setup-shell"
        "shell-init"
        "help"
    )

    local missing=""
    for cmd in "${commands[@]}"; do
        if ! grep -q "'$cmd:" "$completions_file"; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        echo "Missing zsh completions for:$missing" >&2
        return 1
    fi
}

# ============================================
# All commands have bash completions
# ============================================

@test "bash completions include main commands" {
    local completions_file="$PWD_DIR/completions/pwt.bash"

    # Check _pwt_commands variable contains key commands
    run grep "_pwt_commands=" "$completions_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"create"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"remove"* ]]
    [[ "$output" == *"server"* ]]
    [[ "$output" == *"status"* ]]
}

@test "bash completions have valid syntax" {
    run bash -n "$PWD_DIR/completions/pwt.bash"
    [ "$status" -eq 0 ]
}

@test "bash completions define _pwt function" {
    run grep "^_pwt()" "$PWD_DIR/completions/pwt.bash"
    [ "$status" -eq 0 ]
}

@test "bash completions register with complete" {
    run grep "complete -F _pwt pwt" "$PWD_DIR/completions/pwt.bash"
    [ "$status" -eq 0 ]
}

# ============================================
# All commands have fish completions
# ============================================

@test "fish completions include main commands" {
    local completions_file="$PWD_DIR/completions/pwt.fish"

    # Check key commands are present
    local commands=("create" "list" "remove" "server" "status" "cd" "use")

    local missing=""
    for cmd in "${commands[@]}"; do
        if ! grep -q "complete.*-a $cmd" "$completions_file"; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        echo "Missing fish completions for:$missing" >&2
        return 1
    fi
}

@test "fish completions define helper functions" {
    local completions_file="$PWD_DIR/completions/pwt.fish"

    run grep "__pwt_worktrees" "$completions_file"
    [ "$status" -eq 0 ]

    run grep "__pwt_projects" "$completions_file"
    [ "$status" -eq 0 ]
}

@test "fish completions disable file completions" {
    run grep "complete -c pwt -f" "$PWD_DIR/completions/pwt.fish"
    [ "$status" -eq 0 ]
}

# ============================================
# Zsh completions details
# ============================================

@test "zsh completions include worktree parameter for cd command" {
    run grep -A5 "cd|use|server" "$PWD_DIR/completions/_pwt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"_pwt_worktrees"* ]]
}

@test "zsh completions include project actions" {
    run grep "_pwt_project_actions" "$PWD_DIR/completions/_pwt"
    [ "$status" -eq 0 ]
}

@test "zsh completions include meta actions" {
    run grep "_pwt_meta_actions" "$PWD_DIR/completions/_pwt"
    [ "$status" -eq 0 ]
}

@test "zsh completions file has valid syntax structure" {
    # Check for basic zsh completion structure
    run grep "#compdef pwt" "$PWD_DIR/completions/_pwt"
    [ "$status" -eq 0 ]

    run grep "_pwt()" "$PWD_DIR/completions/_pwt"
    [ "$status" -eq 0 ]
}

# ============================================
# Man page exists
# ============================================

@test "man page exists" {
    [ -f "$PWD_DIR/man/pwt.1" ]
}

@test "man page has correct format" {
    run grep "^.TH PWT 1" "$PWD_DIR/man/pwt.1"
    [ "$status" -eq 0 ]
}

@test "man page documents main commands" {
    local manpage="$PWD_DIR/man/pwt.1"

    # Check key sections exist
    run grep "^.SH COMMANDS" "$manpage"
    [ "$status" -eq 0 ]

    run grep "^.SH PWTFILE" "$manpage"
    [ "$status" -eq 0 ]

    run grep "^.SH EXAMPLES" "$manpage"
    [ "$status" -eq 0 ]
}
