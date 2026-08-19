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
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
EOF

    # Add a commit
    cd "$TEST_REPO"
    echo "content" >file.txt
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

@test "pwt <project> <worktree> server passes Pwtfile params" {
    cd "$TEST_REPO"

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    echo "SERVER_PARAM_WT:$PWT_WORKTREE"
    echo "SERVER_PARAM_1:${1:-}"
    echo "SERVER_PARAM_ARGS:$PWT_ARGS"
}
EOF

    "$PWT_BIN" create TEST-PROJ-SERVER-PARAM HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project TEST-PROJ-SERVER-PARAM server stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_PARAM_WT:TEST-PROJ-SERVER-PARAM"* ]]
    [[ "$output" == *"SERVER_PARAM_1:stop"* ]]
    [[ "$output" == *"SERVER_PARAM_ARGS:stop"* ]]
}

@test "pwt <worktree> server passes Pwtfile params inside project" {
    cd "$TEST_REPO"

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    echo "SERVER_PARAM_WT:$PWT_WORKTREE"
    echo "SERVER_PARAM_1:${1:-}"
    echo "SERVER_PARAM_ARGS:$PWT_ARGS"
}
EOF

    "$PWT_BIN" create TEST-WT-SERVER-PARAM HEAD

    run "$PWT_BIN" TEST-WT-SERVER-PARAM server stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_PARAM_WT:TEST-WT-SERVER-PARAM"* ]]
    [[ "$output" == *"SERVER_PARAM_1:stop"* ]]
    [[ "$output" == *"SERVER_PARAM_ARGS:stop"* ]]
    [[ "$output" != *"Starting server"* ]]
}

@test "pwt server passes Pwtfile params inside worktree" {
    cd "$TEST_REPO"

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    echo "SERVER_PARAM_WT:$PWT_WORKTREE"
    echo "SERVER_PARAM_1:${1:-}"
    echo "SERVER_PARAM_ARGS:$PWT_ARGS"
}
EOF

    "$PWT_BIN" create TEST-IN-WT-SERVER-PARAM HEAD
    cd "$TEST_WORKTREES/TEST-IN-WT-SERVER-PARAM"

    run "$PWT_BIN" server stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_PARAM_WT:TEST-IN-WT-SERVER-PARAM"* ]]
    [[ "$output" == *"SERVER_PARAM_1:stop"* ]]
    [[ "$output" == *"SERVER_PARAM_ARGS:stop"* ]]
}

# ============================================
# Pwtfile arguments vs worktree names
# Regression: `pwt server stop` inside a worktree reached through the
# project's `current` symlink was read as a worktree named "stop", because
# $PWD is .../projects/<p>/current and never matches $WORKTREES_DIR.
# ============================================

_seed_arg_echo_pwtfile() {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    echo "ARGS=[$PWT_ARGS]"
}
EOF
    cd "$TEST_REPO"
    git add Pwtfile
    git commit -q -m "Add Pwtfile"
}

@test "server passes an unknown positional as a Pwtfile arg from inside a worktree" {
    _seed_arg_echo_pwtfile
    "$PWT_BIN" create ARG-WT HEAD >/dev/null 2>&1

    cd "$TEST_WORKTREES/ARG-WT"
    run "$PWT_BIN" server stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS=[stop]"* ]]
    [[ "$output" != *"Worktree not found"* ]]
}

@test "server passes an unknown positional as a Pwtfile arg via the current symlink" {
    _seed_arg_echo_pwtfile
    "$PWT_BIN" create ARG-WT HEAD >/dev/null 2>&1
    "$PWT_BIN" use ARG-WT >/dev/null 2>&1

    local current_link="$PWT_DIR/projects/test-project/current"
    [ -L "$current_link" ] || skip "current symlink was not created"

    cd "$current_link"
    run "$PWT_BIN" server stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS=[stop]"* ]]
    [[ "$output" != *"Worktree not found"* ]]
}

@test "server from the main app still treats an unknown name as a worktree" {
    # Deliberate asymmetry: inside a worktree the context is unambiguous, so
    # an unknown positional is a Pwtfile arg; from the main app it is far more
    # likely a mistyped worktree name, so it must still fail.
    _seed_arg_echo_pwtfile

    cd "$TEST_REPO"
    run "$PWT_BIN" server definitely-not-a-worktree
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "server still resolves a real worktree name instead of treating it as an arg" {
    _seed_arg_echo_pwtfile
    "$PWT_BIN" create ARG-WT HEAD >/dev/null 2>&1
    "$PWT_BIN" use ARG-WT >/dev/null 2>&1

    local current_link="$PWT_DIR/projects/test-project/current"
    [ -L "$current_link" ] || skip "current symlink was not created"

    cd "$current_link"
    run "$PWT_BIN" server ARG-WT
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS=[]"* ]]
}

# ============================================
# The announced port must not overclaim
# ============================================
# Real case: a Pwtfile whose server() deliberately binds a fixed port
# (a browser extension has the URL baked in), while pwt announced
# "Starting server on port 5000..." - the allocated port, stated as if
# it were where the server will listen. pwt cannot know that; only a
# server() that consumes $PWT_PORT makes the claim true.

@test "server announces the port as fact only when the Pwtfile uses PWT_PORT" {
    cat >"$TEST_REPO/Pwtfile" <<'PWTEOF'
server() {
    echo "SERVER_RAN on $PWT_PORT"
}
PWTEOF
    cd "$TEST_REPO"
    run "$PWT_BIN" server
    [[ "$output" == *"Starting server on port"* ]] || {
        echo "a PWT_PORT-honoring Pwtfile keeps the direct message: $output" >&2
        return 1
    }
}

@test "server does not claim a port the Pwtfile never reads" {
    cat >"$TEST_REPO/Pwtfile" <<'PWTEOF'
# extension talks to a fixed localhost URL; deliberately not $PWT_PORT
# (this comment is the trap: the string appears, the variable is unused)
server() {
    echo "SERVER_RAN on fixed 8787"
}
PWTEOF
    cd "$TEST_REPO"
    run "$PWT_BIN" server
    [[ "$output" != *"Starting server on port"* ]] || {
        echo "pwt announced a port the server() never reads: $output" >&2
        return 1
    }
    [[ "$output" == *"allocated"* ]] || {
        echo "the allocated port should still be stated as allocation: $output" >&2
        return 1
    }
    [[ "$output" == *"SERVER_RAN"* ]]
}
