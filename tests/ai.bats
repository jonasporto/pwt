#!/usr/bin/env bats
# Tests for pwt ai command
# Verifies AI tool management and execution

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

    # Mock AI commands
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" << 'EOF'
#!/bin/bash
echo "mock-claude: $@"
echo "pwd: $(pwd)"
EOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"

    cat > "$TEST_TEMP_DIR/bin/gemini" << 'EOF'
#!/bin/bash
echo "mock-gemini: $@"
echo "pwd: $(pwd)"
EOF
    chmod +x "$TEST_TEMP_DIR/bin/gemini"

    cat > "$TEST_TEMP_DIR/bin/codex" << 'EOF'
#!/bin/bash
echo "mock-codex: $@"
echo "pwd: $(pwd)"
EOF
    chmod +x "$TEST_TEMP_DIR/bin/codex"

    export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

teardown() {
    teardown_test_env
}

# ============================================
# ai add
# ============================================

@test "pwt ai add creates tool config" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai add claude "claude"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added 'claude'"* ]]

    # Verify in config
    run jq -r '.ai.tools.claude' "$PWT_DIR/config.json"
    [ "$output" = "claude" ]
}

@test "pwt ai add with options" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai add gemini "gemini --model gemini-2.0-flash"
    [ "$status" -eq 0 ]

    run jq -r '.ai.tools.gemini' "$PWT_DIR/config.json"
    [ "$output" = "gemini --model gemini-2.0-flash" ]
}

@test "pwt ai add without args shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai add
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "pwt ai add without command shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai add myname
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ============================================
# ai remove
# ============================================

@test "pwt ai remove deletes tool" {
    cd "$TEST_REPO"
    "$PWT_BIN" ai add gemini "gemini"

    run "$PWT_BIN" ai remove gemini
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed"* ]]

    run jq -r '.ai.tools.gemini // "null"' "$PWT_DIR/config.json"
    [ "$output" = "null" ]
}

@test "pwt ai remove without arg shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# ============================================
# ai list
# ============================================

@test "pwt ai list shows configured tools" {
    cd "$TEST_REPO"
    "$PWT_BIN" ai add claude "claude"
    "$PWT_BIN" ai add gemini "gemini --model gemini-2.0-flash"

    run "$PWT_BIN" ai list
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"* ]]
    [[ "$output" == *"gemini"* ]]
}

@test "pwt ai list empty shows hint" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No tools configured"* ]]
    [[ "$output" == *"pwt ai:claude"* ]]
}

@test "pwt ai list shows default marker" {
    cd "$TEST_REPO"
    "$PWT_BIN" ai add claude "claude"
    "$PWT_BIN" ai:claude --default

    run "$PWT_BIN" ai list
    [[ "$output" == *"(default)"* ]]
}

# ============================================
# ai --default
# ============================================

@test "pwt ai:tool --default sets default" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai:gemini --default
    [ "$status" -eq 0 ]

    run jq -r '.ai.default' "$PWT_DIR/config.json"
    [ "$output" = "gemini" ]
}

@test "pwt ai:tool --default shows confirmation" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai:codex --default
    [ "$status" -eq 0 ]
    [[ "$output" == *"Default set to 'codex'"* ]]
}

# ============================================
# ai execution
# ============================================

@test "pwt ai runs default tool (claude)" {
    cd "$TEST_REPO"

    run "$PWT_BIN" ai
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-claude"* ]]
}

@test "pwt ai runs configured default" {
    cd "$TEST_REPO"
    "$PWT_BIN" ai add gemini "gemini"
    "$PWT_BIN" ai:gemini --default

    run "$PWT_BIN" ai
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-gemini"* ]]
}

@test "pwt ai:tool runs specific tool" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai:gemini
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-gemini"* ]]
}

@test "pwt ai:tool uses configured command" {
    cd "$TEST_REPO"
    "$PWT_BIN" ai add mygem "gemini --model gemini-2.0-flash"

    run "$PWT_BIN" ai:mygem
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-gemini: --model gemini-2.0-flash"* ]]
}

@test "pwt ai WORKTREE runs in worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-WT HEAD

    run "$PWT_BIN" ai TEST-WT
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwd: $TEST_WORKTREES/TEST-WT"* ]]
}

@test "pwt ai:tool WORKTREE runs tool in worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-WT2 HEAD

    run "$PWT_BIN" ai:gemini TEST-WT2
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-gemini"* ]]
    [[ "$output" == *"pwd: $TEST_WORKTREES/TEST-WT2"* ]]
}

@test "pwt ai @ runs in main" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai @
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwd: $TEST_REPO"* ]]
}

@test "pwt ai -- args passes extra arguments" {
    cd "$TEST_REPO"

    run "$PWT_BIN" ai -- --resume --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-claude: --resume --verbose"* ]]
}

@test "pwt ai:tool -- args passes extra arguments" {
    cd "$TEST_REPO"

    run "$PWT_BIN" ai:codex -- --full-auto
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-codex: --full-auto"* ]]
}

@test "pwt ai WORKTREE -- args combines all" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-ARGS HEAD

    run "$PWT_BIN" ai TEST-ARGS -- --continue
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-claude: --continue"* ]]
    [[ "$output" == *"pwd: $TEST_WORKTREES/TEST-ARGS"* ]]
}

# ============================================
# PATH fallback
# ============================================

@test "pwt ai:tool falls back to PATH" {
    cd "$TEST_REPO"
    # gemini is not configured but exists in PATH
    run "$PWT_BIN" ai:gemini
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-gemini"* ]]
}

@test "pwt ai:unknown fails gracefully" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai:nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"command found"* ]]
}

# ============================================
# --add flag
# ============================================

@test "pwt ai:tool --add saves and runs" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai:gemini --add
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added 'gemini'"* ]]
    [[ "$output" == *"mock-gemini"* ]]

    # Verify saved
    run jq -r '.ai.tools.gemini' "$PWT_DIR/config.json"
    [ "$output" = "gemini" ]
}

@test "pwt ai:tool --add fails for unknown command" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai:nonexistent --add
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found in PATH"* ]]
}

# ============================================
# help
# ============================================

@test "pwt ai help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"pwt ai add"* ]]
}

@test "pwt ai --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "pwt ai -h shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ============================================
# error handling
# ============================================

@test "pwt ai fails for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" ai NONEXISTENT
    [ "$status" -eq 1 ]
    [[ "$output" == *"Worktree not found"* ]]
}

# ============================================
# project prefix
# ============================================

@test "pwt <project> ai works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project ai WT-REMOTE
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-claude"* ]]
}

@test "pwt <project> ai:tool works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE2 HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project ai:gemini WT-REMOTE2
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock-gemini"* ]]
}
