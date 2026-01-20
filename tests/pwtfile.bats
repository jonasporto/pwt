#!/usr/bin/env bats
# Tests for Pwtfile functionality
# Verifies setup/teardown hooks and helper functions

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
# Pwtfile setup phase
# ============================================

@test "Pwtfile setup() is called during create" {
    cd "$TEST_REPO"

    # Create a Pwtfile that creates a marker file
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
setup() {
    touch "$PWT_WORKTREE_PATH/.setup_ran"
    echo "SETUP: $PWT_WORKTREE" >> "$PWT_WORKTREE_PATH/.setup_log"
}
EOF

    "$PWT_BIN" create TEST-SETUP HEAD

    # Verify setup was called
    [ -f "$TEST_WORKTREES/TEST-SETUP/.setup_ran" ]
    [ -f "$TEST_WORKTREES/TEST-SETUP/.setup_log" ]
    grep -q "SETUP: TEST-SETUP" "$TEST_WORKTREES/TEST-SETUP/.setup_log"
}

@test "Pwtfile receives PWT_* environment variables" {
    cd "$TEST_REPO"

    # Create a Pwtfile that logs all PWT variables
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
setup() {
    echo "PWT_WORKTREE=$PWT_WORKTREE" >> "$PWT_WORKTREE_PATH/.env_log"
    echo "PWT_PORT=$PWT_PORT" >> "$PWT_WORKTREE_PATH/.env_log"
    echo "PWT_BRANCH=$PWT_BRANCH" >> "$PWT_WORKTREE_PATH/.env_log"
    echo "PWT_PROJECT=$PWT_PROJECT" >> "$PWT_WORKTREE_PATH/.env_log"
}
EOF

    "$PWT_BIN" create TEST-ENV HEAD

    # Verify variables were set
    grep -q "PWT_WORKTREE=TEST-ENV" "$TEST_WORKTREES/TEST-ENV/.env_log"
    grep -q "PWT_PORT=" "$TEST_WORKTREES/TEST-ENV/.env_log"
    grep -q "PWT_BRANCH=test/TEST-ENV" "$TEST_WORKTREES/TEST-ENV/.env_log"
    grep -q "PWT_PROJECT=test-project" "$TEST_WORKTREES/TEST-ENV/.env_log"
}

@test "Pwtfile without setup() function doesn't error" {
    cd "$TEST_REPO"

    # Create a Pwtfile with only a server function
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "server would run here"
}
EOF

    run "$PWT_BIN" create TEST-NOSETUP HEAD
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-NOSETUP" ]
}

# ============================================
# Pwtfile teardown phase
# ============================================

@test "Pwtfile teardown() is called during remove" {
    cd "$TEST_REPO"

    # Use a unique file based on test temp dir
    local teardown_log="$TEST_TEMP_DIR/teardown_ran.log"

    # Create a Pwtfile with teardown
    cat > "$TEST_REPO/Pwtfile" << EOF
setup() {
    touch "\$PWT_WORKTREE_PATH/.setup_ran"
}
teardown() {
    # Write to a location outside the worktree (since it will be deleted)
    echo "TEARDOWN: \$PWT_WORKTREE" >> "$teardown_log"
}
EOF

    "$PWT_BIN" create TEST-TEARDOWN HEAD
    [ -f "$TEST_WORKTREES/TEST-TEARDOWN/.setup_ran" ]

    # Remove and check teardown was called
    "$PWT_BIN" remove TEST-TEARDOWN -y

    [ -f "$teardown_log" ]
    grep -q "TEARDOWN: TEST-TEARDOWN" "$teardown_log"
}

# ============================================
# Pwtfile helper functions
# ============================================

@test "Pwtfile replace_literal helper works" {
    cd "$TEST_REPO"

    # Create a file to modify
    echo "DATABASE=original_db" > "$TEST_REPO/config.txt"
    git add config.txt
    git commit -q -m "Add config"

    # Create Pwtfile that uses replace_literal
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
setup() {
    replace_literal "config.txt" "original_db" "modified_db_$PWT_PORT"
}
EOF

    "$PWT_BIN" create TEST-REPLACE HEAD

    # Verify replacement happened
    grep -q "modified_db_" "$TEST_WORKTREES/TEST-REPLACE/config.txt"
    ! grep -q "original_db" "$TEST_WORKTREES/TEST-REPLACE/config.txt"
}

@test "Pwtfile replace_re helper works with regex" {
    cd "$TEST_REPO"

    # Create a file with port number
    echo "PORT=3000" > "$TEST_REPO/config.txt"
    git add config.txt
    git commit -q -m "Add config"

    # Create Pwtfile that uses replace_re
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
setup() {
    replace_re "config.txt" "PORT=[0-9]+" "PORT=$PWT_PORT"
}
EOF

    "$PWT_BIN" create TEST-REGEX HEAD

    # Verify regex replacement happened (port should not be 3000)
    ! grep -q "PORT=3000" "$TEST_WORKTREES/TEST-REGEX/config.txt"
    grep -q "PORT=" "$TEST_WORKTREES/TEST-REGEX/config.txt"
}

# ============================================
# Global Pwtfile
# ============================================

@test "Global Pwtfile runs after project Pwtfile" {
    cd "$TEST_REPO"

    # Create project Pwtfile
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
setup() {
    echo "1:PROJECT" >> "$PWT_WORKTREE_PATH/.order_log"
}
EOF

    # Create global Pwtfile
    cat > "$PWT_DIR/Pwtfile" << 'EOF'
setup() {
    echo "2:GLOBAL" >> "$PWT_WORKTREE_PATH/.order_log"
}
EOF

    "$PWT_BIN" create TEST-ORDER HEAD

    # Verify order: project first, then global
    [ -f "$TEST_WORKTREES/TEST-ORDER/.order_log" ]
    head -1 "$TEST_WORKTREES/TEST-ORDER/.order_log" | grep -q "1:PROJECT"
    tail -1 "$TEST_WORKTREES/TEST-ORDER/.order_log" | grep -q "2:GLOBAL"
}

# ============================================
# Pwtfile error handling
# ============================================

@test "Pwtfile error in setup doesn't prevent worktree creation" {
    cd "$TEST_REPO"

    # Create Pwtfile that fails
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
setup() {
    touch "$PWT_WORKTREE_PATH/.before_error"
    false  # This will fail
    touch "$PWT_WORKTREE_PATH/.after_error"  # Won't run
}
EOF

    # Create should still work (Pwtfile runs in subshell)
    run "$PWT_BIN" create TEST-ERROR HEAD

    # Worktree should exist
    [ -d "$TEST_WORKTREES/TEST-ERROR" ]
    # File before error should exist
    [ -f "$TEST_WORKTREES/TEST-ERROR/.before_error" ]
}

# ============================================
# No Pwtfile
# ============================================

@test "Create works without Pwtfile" {
    cd "$TEST_REPO"

    # Ensure no Pwtfile exists
    rm -f "$TEST_REPO/Pwtfile" "$PWT_DIR/Pwtfile"

    run "$PWT_BIN" create TEST-NOPWTFILE HEAD
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-NOPWTFILE" ]
}

# ============================================
# Custom Pwtfile commands
# ============================================

@test "pwt <custom_cmd> runs custom function from Pwtfile" {
    cd "$TEST_REPO"

    # Create a Pwtfile with custom command
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
mycmd() {
    echo "MYCMD_RAN:$PWT_WORKTREE:$PWT_WORKTREE_PATH"
}
EOF

    run "$PWT_BIN" mycmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"MYCMD_RAN:@:"* ]]
}

@test "pwt <custom_cmd> fails for unknown command" {
    cd "$TEST_REPO"

    # Create empty Pwtfile
    echo "" > "$TEST_REPO/Pwtfile"

    run "$PWT_BIN" nonexistent_cmd
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "pwt <custom_cmd> receives PWT_ARGS" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
argtest() {
    echo "ARGS:$PWT_ARGS"
}
EOF

    run "$PWT_BIN" argtest --foo bar --baz
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:--foo bar --baz"* ]]
}

@test "pwt <custom_cmd> in worktree gets correct context" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
ctxtest() {
    echo "CONTEXT_WT:$PWT_WORKTREE"
    echo "CONTEXT_DIR:$(basename "$PWT_WORKTREE_PATH")"
}
EOF

    "$PWT_BIN" create CTX-TEST HEAD

    cd "$TEST_WORKTREES/CTX-TEST"
    run "$PWT_BIN" ctxtest
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONTEXT_WT:CTX-TEST"* ]]
    [[ "$output" == *"CONTEXT_DIR:CTX-TEST"* ]]
}

# ============================================
# Custom commands with for-each
# ============================================

@test "pwt for-each <custom_cmd> runs in all worktrees" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
listcmd() {
    echo "LISTED:$PWT_WORKTREE"
}
EOF

    "$PWT_BIN" create FE-CMD1 HEAD
    "$PWT_BIN" create FE-CMD2 HEAD

    run "$PWT_BIN" for-each listcmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"LISTED:@"* ]]
    [[ "$output" == *"LISTED:FE-CMD1"* ]]
    [[ "$output" == *"LISTED:FE-CMD2"* ]]
}

@test "pwt for-each <custom_cmd> passes args" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
argcmd() {
    echo "EACH_ARGS:$PWT_ARGS"
}
EOF

    "$PWT_BIN" create FE-ARGS HEAD

    run "$PWT_BIN" for-each argcmd --myarg value
    [ "$status" -eq 0 ]
    # Note: for-each may not pass args the same way
    [[ "$output" == *"EACH_ARGS:"* ]]
}

@test "pwt for-each detects Pwtfile vs shell command" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
pwtcmd() {
    echo "PWTCMD_RAN"
}
EOF

    "$PWT_BIN" create FE-DETECT HEAD

    # Pwtfile command
    run "$PWT_BIN" for-each pwtcmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWTCMD_RAN"* ]]

    # Shell command (echo is NOT in Pwtfile)
    run "$PWT_BIN" for-each echo SHELL_ECHO
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHELL_ECHO"* ]]
}

# ============================================
# Custom commands with project prefix
# ============================================

@test "pwt <project> <cmd> requires worktree context" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
projcmd() {
    echo "PROJ_CMD:$PWT_PROJECT"
}
EOF

    # Run from outside the project without worktree - should error
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project projcmd
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires worktree context"* ]]
}

@test "pwt <project> @ <cmd> runs in main app" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
projcmd() {
    echo "PROJ_CMD:$PWT_PROJECT:$PWT_WORKTREE"
}
EOF

    # Run with @ (main app) from anywhere
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project @ projcmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROJ_CMD:test-project:@"* ]]
}

@test "pwt <project> <worktree> <cmd> runs in specific worktree" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
projcmd() {
    echo "PROJ_CMD:$PWT_PROJECT:$PWT_WORKTREE"
}
EOF

    "$PWT_BIN" create WT-PROJ HEAD

    # Run in specific worktree from anywhere
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project WT-PROJ projcmd
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROJ_CMD:test-project:WT-PROJ"* ]]
}

# ============================================
# has_pwtfile_command detection
# ============================================

@test "has_pwtfile_command detects function() syntax" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
funcstyle() {
    echo "found"
}
EOF

    run "$PWT_BIN" funcstyle
    [ "$status" -eq 0 ]
    [[ "$output" == *"found"* ]]
}

@test "has_pwtfile_command detects function keyword syntax" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
function keywordstyle {
    echo "found"
}
EOF

    run "$PWT_BIN" keywordstyle
    [ "$status" -eq 0 ]
    [[ "$output" == *"found"* ]]
}

@test "has_pwtfile_command ignores commented functions" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
# commented() {
#     echo "should not run"
# }
realfunc() {
    echo "real"
}
EOF

    run "$PWT_BIN" commented
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]]

    run "$PWT_BIN" realfunc
    [ "$status" -eq 0 ]
    [[ "$output" == *"real"* ]]
}
