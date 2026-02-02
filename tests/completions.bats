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

# ============================================
# Trailing slash normalization (shell completion)
# ============================================

# Test that commands accept names with trailing slash (from shell completion)
# This ensures that tab completion works correctly with all worktree commands

@test "commands handle trailing slash: resolve_worktree_path normalizes name" {
    # This tests the core function used by multiple commands
    local completions_file="$PWD_DIR/completions/pwt.bash"

    # Verify that the normalize pattern exists in main pwt file
    run grep "target.*%/" "$PWD_DIR/bin/pwt"
    [ "$status" -eq 0 ]
}

@test "commands handle trailing slash: cmd_cd strips slash" {
    run grep -A3 "Strip trailing slash" "$PWD_DIR/bin/pwt"
    [ "$status" -eq 0 ]
    [[ "$output" == *'${target%/}'* ]]
}

@test "commands handle trailing slash: cmd_remove strips slash" {
    run grep -A3 "strip trailing slash" "$PWD_DIR/lib/pwt/worktree.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'${name%/}'* ]]
}

@test "require_project error messages go to stderr not stdout" {
    # Test that error messages from require_project go to stderr
    # This is critical for shell completions which capture stdout
    run grep ">&2" "$PWD_DIR/bin/pwt"
    [ "$status" -eq 0 ]
    # Verify the specific error message about initialization goes to stderr
    run grep "Run from inside a git repository.*>&2" "$PWD_DIR/bin/pwt"
    [ "$status" -eq 0 ]
}

# ============================================
# Shell completion integration tests
# ============================================

@test "zsh completion _pwt_worktrees function finds binary" {
    # Verify the completion script has logic to find the pwt binary
    run grep -E "commands\[pwt\]|whence -p pwt" "$PWD_DIR/completions/_pwt"
    [ "$status" -eq 0 ]
}

@test "zsh completion calls list --names with stderr suppressed" {
    # Critical: completions must suppress stderr to avoid error messages in completion list
    run grep "list --names 2>/dev/null" "$PWD_DIR/completions/_pwt"
    [ "$status" -eq 0 ]
}

@test "list --names returns only worktree names (no errors to stdout)" {
    setup_test_env

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-comp"
    cat > "$PWT_DIR/projects/test-comp/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_TEMP_DIR/worktrees"
}
EOF
    mkdir -p "$TEST_TEMP_DIR/worktrees"

    cd "$TEST_REPO"

    # Capture stdout and stderr separately
    local stdout_file="$TEST_TEMP_DIR/stdout"
    local stderr_file="$TEST_TEMP_DIR/stderr"

    "$PWT_BIN" list --names >"$stdout_file" 2>"$stderr_file"

    # stdout should only contain worktree names (one per line, ending with /)
    # and nothing else (no error messages)
    while IFS= read -r line; do
        # Each line should be either "@/" or a worktree name ending with /
        [[ "$line" =~ ^[a-zA-Z0-9_@-]+/$ ]] || {
            echo "Invalid line in stdout: '$line'" >&2
            return 1
        }
    done < "$stdout_file"

    teardown_test_env
}

@test "list --names errors go to stderr not stdout" {
    setup_test_env

    # Try to run list --names outside any project (should error)
    cd "$TEST_TEMP_DIR"

    # Capture stdout and stderr separately
    local stdout_file="$TEST_TEMP_DIR/stdout"
    local stderr_file="$TEST_TEMP_DIR/stderr"

    # This should fail (no project)
    "$PWT_BIN" list --names >"$stdout_file" 2>"$stderr_file" || true

    # stdout should be empty (no error messages)
    [ ! -s "$stdout_file" ] || {
        echo "Unexpected stdout: $(cat "$stdout_file")" >&2
        return 1
    }

    # stderr should have the error message
    [ -s "$stderr_file" ]

    teardown_test_env
}
