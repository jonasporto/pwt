#!/usr/bin/env bats
# Tests for pwt plugin system
# Verifies plugin loading, management, and execution

load test_helper

setup() {
    setup_test_env

    # Set up worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Configure test project
    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config.json" << EOF
{
    "path": "$TEST_REPO",
    "worktrees_dir": "$TEST_WORKTREES"
}
EOF

    # Create plugins directory
    mkdir -p "$PWT_DIR/plugins"
}

teardown() {
    teardown_test_env
}

# ============================================
# Plugin management: pwt plugin
# ============================================

@test "pwt plugin list shows no plugins when empty" {
    run "$PWT_BIN" plugin list
    [ "$status" -eq 0 ]
    [[ "$output" == *"no plugins installed"* ]]
}

@test "pwt plugin list shows installed plugins" {
    # Create a simple test plugin
    cat > "$PWT_DIR/plugins/pwt-test" << 'EOF'
#!/bin/bash
# Description: Test plugin
# Version: 1.0.0
echo "test plugin"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-test"

    run "$PWT_BIN" plugin list
    [ "$status" -eq 0 ]
    [[ "$output" == *"test"* ]]
}

@test "pwt plugin path returns plugins directory" {
    run "$PWT_BIN" plugin path
    [ "$status" -eq 0 ]
    [[ "$output" == *"plugins"* ]]
}

@test "pwt plugin create creates new plugin from template" {
    run "$PWT_BIN" plugin create mytest
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created plugin"* ]]

    # Verify plugin was created
    [ -f "$PWT_DIR/plugins/pwt-mytest" ]
    [ -x "$PWT_DIR/plugins/pwt-mytest" ]
}

@test "pwt plugin create fails if plugin already exists" {
    # Create first
    "$PWT_BIN" plugin create existing

    # Try to create again
    run "$PWT_BIN" plugin create existing
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "pwt plugin install copies local file" {
    # Create a plugin file
    local plugin_file="$TEST_TEMP_DIR/my-plugin.sh"
    cat > "$plugin_file" << 'EOF'
#!/bin/bash
echo "installed plugin"
EOF

    run "$PWT_BIN" plugin install "$plugin_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed plugin"* ]]

    # Verify installed
    [ -x "$PWT_DIR/plugins/pwt-my-plugin.sh" ]
}

@test "pwt plugin remove deletes plugin" {
    # Create plugin first
    "$PWT_BIN" plugin create removeme

    # Verify exists
    [ -f "$PWT_DIR/plugins/pwt-removeme" ]

    # Remove it
    run "$PWT_BIN" plugin remove removeme
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed plugin"* ]]

    # Verify removed
    [ ! -f "$PWT_DIR/plugins/pwt-removeme" ]
}

@test "pwt plugin remove fails for non-existent plugin" {
    run "$PWT_BIN" plugin remove nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "pwt plugin help shows usage" {
    run "$PWT_BIN" plugin help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"create"* ]]
}

# ============================================
# Plugin execution
# ============================================

@test "pwt executes plugin when command matches" {
    # Create a simple plugin
    cat > "$PWT_DIR/plugins/pwt-hello" << 'EOF'
#!/bin/bash
echo "Hello from plugin!"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-hello"

    run "$PWT_BIN" hello
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hello from plugin!"* ]]
}

@test "plugin receives arguments" {
    cat > "$PWT_DIR/plugins/pwt-echo" << 'EOF'
#!/bin/bash
echo "args: $@"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-echo"

    run "$PWT_BIN" echo arg1 arg2 arg3
    [ "$status" -eq 0 ]
    [[ "$output" == *"args: arg1 arg2 arg3"* ]]
}

@test "plugin receives PWT_DIR environment variable" {
    cat > "$PWT_DIR/plugins/pwt-showdir" << 'EOF'
#!/bin/bash
echo "dir: $PWT_DIR"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-showdir"

    run "$PWT_BIN" showdir
    [ "$status" -eq 0 ]
    [[ "$output" == *"dir: $PWT_DIR"* ]]
}

@test "plugin receives PWT_PROJECT when in project" {
    cat > "$PWT_DIR/plugins/pwt-showproject" << 'EOF'
#!/bin/bash
echo "project: ${PWT_PROJECT:-none}"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-showproject"

    cd "$TEST_REPO"
    run "$PWT_BIN" showproject
    [ "$status" -eq 0 ]
    [[ "$output" == *"project: test-project"* ]]
}

@test "plugin receives PWT_MAIN_APP when in project" {
    cat > "$PWT_DIR/plugins/pwt-showapp" << 'EOF'
#!/bin/bash
echo "app: ${PWT_MAIN_APP:-none}"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-showapp"

    cd "$TEST_REPO"
    run "$PWT_BIN" showapp
    [ "$status" -eq 0 ]
    [[ "$output" == *"app: $TEST_REPO"* ]]
}

@test "plugin receives PWT_WORKTREES_DIR when in project" {
    cat > "$PWT_DIR/plugins/pwt-showwt" << 'EOF'
#!/bin/bash
echo "worktrees: ${PWT_WORKTREES_DIR:-none}"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-showwt"

    cd "$TEST_REPO"
    run "$PWT_BIN" showwt
    [ "$status" -eq 0 ]
    [[ "$output" == *"worktrees: $TEST_WORKTREES"* ]]
}

# ============================================
# Plugin priority
# ============================================

@test "plugin takes priority over unknown command error" {
    # Without plugin, should get "Unknown command"
    run "$PWT_BIN" customcmd
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]]

    # Create plugin
    cat > "$PWT_DIR/plugins/pwt-customcmd" << 'EOF'
#!/bin/bash
echo "custom command works"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-customcmd"

    # With plugin, should work
    run "$PWT_BIN" customcmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"custom command works"* ]]
}

@test "plugins appear in command suggestions" {
    cat > "$PWT_DIR/plugins/pwt-deploy" << 'EOF'
#!/bin/bash
echo "deploy"
EOF
    chmod +x "$PWT_DIR/plugins/pwt-deploy"

    # Typo should suggest plugin
    run "$PWT_BIN" deplyo
    [ "$status" -ne 0 ]
    [[ "$output" == *"deploy"* ]] || [[ "$output" == *"Unknown command"* ]]
}

# ============================================
# Plugin with subcommands
# ============================================

@test "plugin can have subcommands" {
    cat > "$PWT_DIR/plugins/pwt-multi" << 'EOF'
#!/bin/bash
case "${1:-}" in
    sub1) echo "subcommand 1" ;;
    sub2) echo "subcommand 2" ;;
    *) echo "usage: pwt multi [sub1|sub2]" ;;
esac
EOF
    chmod +x "$PWT_DIR/plugins/pwt-multi"

    run "$PWT_BIN" multi sub1
    [ "$status" -eq 0 ]
    [[ "$output" == *"subcommand 1"* ]]

    run "$PWT_BIN" multi sub2
    [ "$status" -eq 0 ]
    [[ "$output" == *"subcommand 2"* ]]
}

# ============================================
# Plugin error handling
# ============================================

@test "plugin exit code is propagated" {
    cat > "$PWT_DIR/plugins/pwt-fail" << 'EOF'
#!/bin/bash
exit 42
EOF
    chmod +x "$PWT_DIR/plugins/pwt-fail"

    run "$PWT_BIN" fail
    [ "$status" -eq 42 ]
}

@test "non-executable plugin is not run" {
    cat > "$PWT_DIR/plugins/pwt-noexec" << 'EOF'
#!/bin/bash
echo "should not run"
EOF
    # Intentionally NOT chmod +x

    run "$PWT_BIN" noexec
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]]
}

# ============================================
# Built-in plugins (pwt-aitools, pwt-extras)
# ============================================

@test "pwt-aitools plugin help works" {
    # Copy plugin to test dir
    cp "$PWD_DIR/plugins/pwt-aitools" "$PWT_DIR/plugins/"

    run "$PWT_BIN" aitools help
    [ "$status" -eq 0 ]
    [[ "$output" == *"topology"* ]]
    [[ "$output" == *"context"* ]]
}

@test "pwt-extras plugin help works" {
    cp "$PWD_DIR/plugins/pwt-extras" "$PWT_DIR/plugins/"

    run "$PWT_BIN" extras help
    [ "$status" -eq 0 ]
    [[ "$output" == *"benchmark"* ]]
    [[ "$output" == *"marker"* ]]
    [[ "$output" == *"conflicts"* ]]
    [[ "$output" == *"prompt"* ]]
}

@test "pwt extras prompt outputs shell snippets" {
    cp "$PWD_DIR/plugins/pwt-extras" "$PWT_DIR/plugins/"

    run "$PWT_BIN" extras prompt zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWT_WORKTREE"* ]]

    run "$PWT_BIN" extras prompt bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"PS1"* ]]
}

@test "pwt aitools context requires project" {
    cp "$PWD_DIR/plugins/pwt-aitools" "$PWT_DIR/plugins/"

    # Run from outside project
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" aitools context
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not in a pwt project"* ]]
}

@test "pwt aitools context works in project" {
    cp "$PWD_DIR/plugins/pwt-aitools" "$PWT_DIR/plugins/"

    cd "$TEST_REPO"
    run "$PWT_BIN" aitools context
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktree Context"* ]]
    [[ "$output" == *"test-project"* ]]
}
