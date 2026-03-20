#!/usr/bin/env bats
# Tests for pwt server command
# Verifies server detection and Pwtfile server phase

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
# Server context detection
# ============================================

@test "pwt server runs on main app when inside main dir" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "MAIN_SERVER: $PWT_WORKTREE on port $PWT_PORT"
}
EOF

    # Ensure no current symlink
    rm -f "$PWT_DIR/projects/test-project/current"

    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAIN_SERVER: @"* ]]
}

@test "pwt server runs on main when current points to @" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "MAIN_VIA_CURRENT: $PWT_WORKTREE on port $PWT_PORT"
}
EOF

    "$PWT_BIN" use @

    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAIN_VIA_CURRENT: @"* ]]
}

@test "pwt server @ runs on main from anywhere" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "MAIN_EXPLICIT: $PWT_WORKTREE on port $PWT_PORT"
}
EOF

    "$PWT_BIN" create TEST-OTHER HEAD
    cd "$TEST_WORKTREES/TEST-OTHER"

    # Explicitly request main app
    run "$PWT_BIN" server @
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAIN_EXPLICIT: @"* ]]
}

@test "pwt server uses BASE_PORT for main app" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
PORT_BASE=5001
server() {
    echo "PORT_IS: $PWT_PORT"
}
EOF

    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"PORT_IS: 5000"* ]]
}

@test "pwt server detects worktree from pwd" {
    cd "$TEST_REPO"

    # Create Pwtfile with server that just echoes and exits
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "SERVER_RAN: $PWT_WORKTREE on port $PWT_PORT"
}
EOF

    "$PWT_BIN" create TEST-SERVER HEAD

    # Run server from inside worktree
    cd "$TEST_WORKTREES/TEST-SERVER"
    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_RAN: TEST-SERVER"* ]]
    [[ "$output" == *"port"* ]]
}

@test "pwt server detects worktree from current symlink" {
    cd "$TEST_REPO"

    # Create Pwtfile with server
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "SERVER_FROM_SYMLINK: $PWT_WORKTREE"
}
EOF

    "$PWT_BIN" create TEST-SYMLINK HEAD
    "$PWT_BIN" use TEST-SYMLINK

    # Run server from unrelated dir (should use current symlink)
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project server
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_FROM_SYMLINK: TEST-SYMLINK"* ]]
    [[ "$output" == *"via symlink"* ]]
}

# ============================================
# Server port detection
# ============================================

@test "pwt server uses port from metadata" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "PORT_IS: $PWT_PORT"
}
EOF

    "$PWT_BIN" create TEST-PORT HEAD

    cd "$TEST_WORKTREES/TEST-PORT"
    run "$PWT_BIN" server

    # Should show the allocated port (not 3000)
    [[ "$output" == *"PORT_IS:"* ]]
    # Port should be a number
    local port=$(echo "$output" | grep "PORT_IS:" | sed 's/.*PORT_IS: //')
    [[ "$port" =~ ^[0-9]+$ ]]
}

# ============================================
# Server Pwtfile execution
# ============================================

@test "pwt server calls Pwtfile server() function" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "CUSTOM_SERVER_FUNCTION"
    echo "WORKTREE=$PWT_WORKTREE"
    echo "PORT=$PWT_PORT"
    echo "PROJECT=$PWT_PROJECT"
}
EOF

    "$PWT_BIN" create TEST-FUNC HEAD

    cd "$TEST_WORKTREES/TEST-FUNC"
    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"CUSTOM_SERVER_FUNCTION"* ]]
    [[ "$output" == *"WORKTREE=TEST-FUNC"* ]]
    [[ "$output" == *"PROJECT=test-project"* ]]
}

@test "pwt server without Pwtfile server() completes without error" {
    cd "$TEST_REPO"

    # Create Pwtfile without server function
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
setup() {
    echo "setup only"
}
EOF

    "$PWT_BIN" create TEST-NOSERVER HEAD

    cd "$TEST_WORKTREES/TEST-NOSERVER"
    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting server"* ]]
}

@test "pwt server without any Pwtfile completes without error" {
    cd "$TEST_REPO"

    # Remove any Pwtfile
    rm -f "$TEST_REPO/Pwtfile" "$PWT_DIR/Pwtfile"

    "$PWT_BIN" create TEST-NOPWT HEAD

    cd "$TEST_WORKTREES/TEST-NOPWT"
    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting server"* ]]
}

# ============================================
# Server working directory
# ============================================

@test "pwt server runs from worktree directory" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "PWD_IS: $(pwd)"
}
EOF

    "$PWT_BIN" create TEST-PWD HEAD

    # Run from unrelated dir via current symlink
    "$PWT_BIN" use TEST-PWD
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project server

    [[ "$output" == *"PWD_IS:"* ]]
    [[ "$output" == *"TEST-PWD"* ]]
}

# ============================================
# Server from different project contexts
# ============================================

@test "pwt <project> server works from anywhere" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "REMOTE_SERVER: $PWT_WORKTREE"
}
EOF

    "$PWT_BIN" create TEST-REMOTE HEAD
    "$PWT_BIN" use TEST-REMOTE

    # Run from unrelated directory
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project server
    [ "$status" -eq 0 ]
    [[ "$output" == *"REMOTE_SERVER: TEST-REMOTE"* ]]
}

# ============================================
# Server with worktree argument
# ============================================

@test "pwt server <worktree> runs server for specified worktree" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "SERVER_ARG: $PWT_WORKTREE on port $PWT_PORT"
}
EOF

    "$PWT_BIN" create TEST-ARG HEAD

    # Run from main repo specifying worktree
    run "$PWT_BIN" server TEST-ARG
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_ARG: TEST-ARG"* ]]
}

@test "pwt server <worktree> works with partial match" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "PARTIAL: $PWT_WORKTREE"
}
EOF

    "$PWT_BIN" create TICKET-12345 HEAD

    # Run with partial name
    run "$PWT_BIN" server 12345
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARTIAL: TICKET-12345"* ]]
}

@test "pwt server <worktree> fails for nonexistent worktree" {
    cd "$TEST_REPO"

    run "$PWT_BIN" server NONEXISTENT
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "pwt <project> server <worktree> works from anywhere" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "PROJ_ARG: $PWT_WORKTREE"
}
EOF

    "$PWT_BIN" create TEST-PROJ-ARG HEAD

    # Run from unrelated directory with project prefix and worktree arg
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project server TEST-PROJ-ARG
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROJ_ARG: TEST-PROJ-ARG"* ]]
}
