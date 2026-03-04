#!/usr/bin/env bats
# Tests for pwt jobs command
# Verifies job listing, stopping, cleaning, and log viewing

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
# pwt jobs list
# ============================================

@test "pwt jobs shows 'no jobs' when empty" {
    run "$PWT_BIN" jobs
    [ "$status" -eq 0 ]
    [[ "$output" == *"No jobs found"* ]]
}

@test "pwt jobs list shows running job" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    sleep 30
}
EOF

    "$PWT_BIN" create TEST-JOBS-LIST HEAD

    cd "$TEST_WORKTREES/TEST-JOBS-LIST"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    # Now list jobs
    run "$PWT_BIN" jobs list
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-JOBS-LIST"* ]]
    [[ "$output" == *"server"* ]]
    [[ "$output" == *"running"* ]]

    # Clean up
    local job_id
    job_id=$(ls "$PWT_DIR/jobs"/*.json 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/.json$//')
    [ -n "$job_id" ] && "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}

# ============================================
# pwt jobs stop
# ============================================

@test "pwt jobs stop kills process" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    sleep 30
}
EOF

    "$PWT_BIN" create TEST-JOBS-STOP HEAD

    cd "$TEST_WORKTREES/TEST-JOBS-STOP"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    # Extract job_id
    local job_id
    job_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')
    [ -n "$job_id" ]

    # Extract PID
    local pid
    pid=$(echo "$output" | grep -o '"pid":[0-9]*' | head -1 | grep -o '[0-9]*')
    [ -n "$pid" ]

    # Process should be running
    kill -0 "$pid" 2>/dev/null

    # Stop the job
    run "$PWT_BIN" jobs stop "$job_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stopped"* ]]

    # Process should be gone (give it a moment)
    sleep 1
    ! kill -0 "$pid" 2>/dev/null
}

@test "pwt jobs stop with no args shows usage" {
    run "$PWT_BIN" jobs stop
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt jobs stop nonexistent job shows error" {
    run "$PWT_BIN" jobs stop nonexistent-id
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# ============================================
# pwt jobs clean
# ============================================

@test "pwt jobs clean removes stale entries" {
    # Create a fake stale job entry
    mkdir -p "$PWT_DIR/jobs"
    cat > "$PWT_DIR/jobs/stale-job-123.json" << EOF
{
  "id": "stale-job-123",
  "pid": 999999,
  "pgid": 999999,
  "command": "server",
  "worktree": "old-wt",
  "project": "test",
  "log": "$PWT_DIR/jobs/stale-job-123.log",
  "started_at": "2024-01-01T00:00:00Z",
  "status": "running"
}
EOF
    touch "$PWT_DIR/jobs/stale-job-123.log"

    run "$PWT_BIN" jobs clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned"* ]]
}

# ============================================
# pwt jobs logs
# ============================================

@test "pwt jobs logs shows output" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    echo "LOG_LINE_1"
    echo "LOG_LINE_2"
    sleep 30
}
EOF

    "$PWT_BIN" create TEST-JOBS-LOGS HEAD

    cd "$TEST_WORKTREES/TEST-JOBS-LOGS"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    local job_id
    job_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')
    [ -n "$job_id" ]

    # Wait for output to appear
    sleep 1

    run "$PWT_BIN" jobs logs "$job_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOG_LINE_1"* ]]
    [[ "$output" == *"LOG_LINE_2"* ]]

    # Clean up
    "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}

@test "pwt jobs logs with no args shows usage" {
    run "$PWT_BIN" jobs logs
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ============================================
# pwt jobs help
# ============================================

@test "pwt jobs help shows usage" {
    run "$PWT_BIN" jobs help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"logs"* ]]
    [[ "$output" == *"stop"* ]]
    [[ "$output" == *"clean"* ]]
}

@test "pwt jobs --help shows usage" {
    run "$PWT_BIN" jobs --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ============================================
# Duplicate detection
# ============================================

@test "pwt server --bg detects duplicate job" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'EOF'
server() {
    sleep 30
}
EOF

    "$PWT_BIN" create TEST-DUP HEAD

    cd "$TEST_WORKTREES/TEST-DUP"

    # Start first instance
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]
    [[ "$output" == *"job_id"* ]]

    local first_job_id
    first_job_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')

    # Try to start second instance - should fail
    run "$PWT_BIN" server --bg
    [ "$status" -ne 0 ]
    [[ "$output" == *"Already running"* ]]

    # Clean up
    "$PWT_BIN" jobs stop "$first_job_id" 2>/dev/null || true
}
