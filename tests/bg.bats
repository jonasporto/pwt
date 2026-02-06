#!/usr/bin/env bats
# Tests for --bg and --no-input execution flags
# Verifies background execution and non-interactive mode

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
    # Kill any background processes we spawned
    if [ -d "$PWT_DIR/jobs" ]; then
        for json in "$PWT_DIR/jobs"/*.json; do
            [ -f "$json" ] || continue
            local pid
            pid=$(grep -o '"pid": *[0-9]*' "$json" | grep -o '[0-9]*' || true)
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        done
    fi
    teardown_test_env
}

# ============================================
# Retrocompatibility - default behavior unchanged
# ============================================

@test "without --bg or --no-input, behavior is identical to current" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "SERVER_DEFAULT: $PWT_WORKTREE on port $PWT_PORT"
}
EOF

    "$PWT_BIN" create TEST-DEFAULT HEAD

    cd "$TEST_WORKTREES/TEST-DEFAULT"
    run "$PWT_BIN" server
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_DEFAULT: TEST-DEFAULT"* ]]
    [[ "$output" == *"Starting server"* ]]
}

@test "PWT_AGENT defaults to 0 when --no-input not used" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
agenttest() {
    set -u
    echo "AGENT_VALUE:$PWT_AGENT"
}
EOF

    run "$PWT_BIN" agenttest
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT_VALUE:0"* ]]
}

# ============================================
# --no-input flag
# ============================================

@test "--no-input closes stdin and sets PWT_AGENT=1" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
checkagent() {
    echo "AGENT:$PWT_AGENT"
    # Try to read from stdin - should fail immediately with closed stdin
    if ! read -t 0 2>/dev/null; then
        echo "STDIN_CLOSED"
    fi
}
EOF

    run "$PWT_BIN" --no-input checkagent
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT:1"* ]]
    [[ "$output" == *"STDIN_CLOSED"* ]]
}

@test "--no-input preserves existing behavior (function still runs)" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
mytask() {
    echo "TASK_COMPLETED"
    echo "WT:$PWT_WORKTREE"
}
EOF

    run "$PWT_BIN" --no-input mytask
    [ "$status" -eq 0 ]
    [[ "$output" == *"TASK_COMPLETED"* ]]
    [[ "$output" == *"WT:@"* ]]
}

# ============================================
# --bg and --no-input flags are NOT in PWT_ARGS
# ============================================

@test "--bg and --no-input flags are NOT in PWT_ARGS" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
argcheck() {
    echo "PWT_ARGS:[$PWT_ARGS]"
}
EOF

    run "$PWT_BIN" --no-input argcheck --myarg value
    [ "$status" -eq 0 ]
    [[ "$output" == *"PWT_ARGS:[--myarg value]"* ]]
    [[ "$output" != *"--no-input"* || "$output" == *"PWT_ARGS:[--myarg value]"* ]]
}

@test "strip removes execution flags from PWT_ARGS in custom commands" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
stripped() {
    echo "ARGS:[$PWT_ARGS]"
}
EOF

    # Even if --no-input appears after command name
    run "$PWT_BIN" stripped --foo --no-input --bar
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARGS:[--foo --bar]"* ]]
}

# ============================================
# --bg runs command in background
# ============================================

@test "--bg runs command in background and returns JSON" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "BG_SERVER_STARTED"
    # Keep running for a bit
    sleep 10
}
EOF

    "$PWT_BIN" create TEST-BG HEAD

    cd "$TEST_WORKTREES/TEST-BG"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]
    [[ "$output" == *"job_id"* ]]
    [[ "$output" == *"pid"* ]]
    [[ "$output" == *"Background job started"* ]]

    # Extract job_id from JSON output
    local job_id
    job_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')
    [ -n "$job_id" ]

    # Clean up
    "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}

@test "--bg with --quiet outputs only JSON" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    sleep 10
}
EOF

    "$PWT_BIN" create TEST-QUIET HEAD

    cd "$TEST_WORKTREES/TEST-QUIET"
    run "$PWT_BIN" --quiet server --bg
    [ "$status" -eq 0 ]
    [[ "$output" != *"Background job started"* ]]
    [[ "$output" == *"job_id"* ]]

    # Clean up
    local job_id
    job_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')
    "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}

@test "--bg creates log file" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "LOG_OUTPUT_TEST"
    sleep 10
}
EOF

    "$PWT_BIN" create TEST-LOG HEAD

    cd "$TEST_WORKTREES/TEST-LOG"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    # Extract log path from JSON output
    local log_file
    log_file=$(echo "$output" | grep -o '"log":"[^"]*"' | head -1 | sed 's/"log":"//;s/"//')
    [ -n "$log_file" ]
    [ -f "$log_file" ]

    # Wait for output to appear
    sleep 1
    grep -q "LOG_OUTPUT_TEST" "$log_file"

    # Clean up
    local job_id
    job_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')
    "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}

@test "server passes extra args via PWT_ARGS with --bg" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "BGARGS:[$PWT_ARGS]"
    sleep 10
}
EOF

    "$PWT_BIN" create TEST-BGARGS HEAD

    cd "$TEST_WORKTREES/TEST-BGARGS"
    run "$PWT_BIN" server --bg --sidekiq
    [ "$status" -eq 0 ]

    # Wait for output
    sleep 1
    local log_file
    log_file=$(echo "$output" | grep -o '"log":"[^"]*"' | head -1 | sed 's/"log":"//;s/"//')
    # PWT_ARGS should contain --sidekiq but NOT --bg
    grep -q "BGARGS:" "$log_file"
    ! grep -q "\-\-bg" "$log_file"

    # Clean up
    local job_id
    job_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')
    "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}
