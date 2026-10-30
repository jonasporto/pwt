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
    # Kill any background processes we spawned
    if [ -d "$PWT_DIR/jobs" ]; then
        for job in "$PWT_DIR/jobs"/*.job; do
            [ -f "$job" ] || continue
            local pid
            pid=$(sed -n 's/^pid=//p' "$job" | head -1 || true)
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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
    job_id=$(ls "$PWT_DIR/jobs"/*.job 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/.job$//')
    [ -n "$job_id" ] && "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}

# ============================================
# pwt jobs stop
# ============================================

@test "pwt jobs stop kills process" {
    cd "$TEST_REPO"

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

    wait_for "! kill -0 $pid" 3
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
    cat >"$PWT_DIR/jobs/stale-job-123.job" <<EOF
id=stale-job-123
pid=999999
pgid=999999
command=server
worktree=old-wt
project=test
log=$PWT_DIR/jobs/stale-job-123.log
started_at=2024-01-01T00:00:00Z
status=running
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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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
    wait_for "grep -q LOG_LINE_1 \"$PWT_DIR/jobs/$job_id.log\"" 3 || true

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

    cat >"$TEST_REPO/Pwtfile" <<'EOF'
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

# Regression: the pid was interpolated raw, so a corrupt record emitted
# "pid":abc - invalid JSON on the path blessed as the consumer API.
@test "jobs list --porcelain emits null for a non-numeric pid" {
    mkdir -p "$PWT_DIR/jobs"
    cat >"$PWT_DIR/jobs/corrupt.job" <<'JOB'
id=corrupt
pid=abc
command=server
worktree=WT-1
project=test-project
log=/tmp/corrupt.log
started_at=2026-01-01T00:00:00Z
status=stopped
JOB

    run "$PWT_BIN" jobs list --porcelain
    [ "$status" -eq 0 ]
    [[ "$output" == *'"pid":null'* ]]
    [[ "$output" != *'"pid":abc'* ]]
}

# ============================================
# Job ids must be unique, even in the same second
# ============================================

@test "two fast launches in the same second keep two job records" {
    # The id is worktree-cmd-epoch; a job that exits instantly frees the
    # duplicate guard, and a relaunch within the same second used to
    # overwrite the first job's record and log
    cat >"$TEST_REPO/Pwtfile" <<'PWTEOF'
blip() { echo "ran"; }
PWTEOF
    cd "$TEST_REPO"
    "$PWT_BIN" blip --bg >/dev/null 2>&1
    "$PWT_BIN" blip --bg >/dev/null 2>&1

    local n
    n=$(ls "$PWT_DIR/jobs"/*.job 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -ge 2 ] || {
        echo "expected 2 job records, found $n (second launch overwrote the first)" >&2
        ls "$PWT_DIR/jobs" >&2 || true
        return 1
    }
}

@test "jobs and logs survive a PWT_DIR containing a space" {
    # jobs.sh iterated $(ls -t ...) unquoted in two places; word splitting
    # broke every path under a directory with a space
    local spaced="$TEST_TEMP_DIR/pwt dir"
    mkdir -p "$spaced"
    cat >"$TEST_REPO/Pwtfile" <<'PWTEOF'
blip() { echo "spaced ran"; }
PWTEOF
    cd "$TEST_REPO"
    PWT_DIR="$spaced" "$PWT_BIN" blip --bg >/dev/null 2>&1
    sleep 1

    PWT_DIR="$spaced" run "$PWT_BIN" jobs list
    [[ "$output" == *"blip"* ]] || {
        echo "jobs list lost the job under a spaced dir: $output" >&2
        return 1
    }

    PWT_DIR="$spaced" run "$PWT_BIN" logs @
    [[ "$output" == *"spaced ran"* ]] || {
        echo "logs could not find the job log: $output" >&2
        return 1
    }
}

# ============================================
# Job lookups by worktree name are scoped to the project
# ============================================

# Two projects with a worktree of the same name (one ticket, two repos):
# a running server in one project must not read as "already running" in
# the other, and the lookups by name (stop, logs, servers) must pick the
# job of the project in scope.
@test "a running server in another project does not block, stop or shadow the same worktree name" {
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'PWTEOF'
server() {
    sleep 30
}
PWTEOF
    "$PWT_BIN" create SAME-NAME HEAD >/dev/null

    # The other project's server job for a worktree with the same name,
    # with a live process behind it
    sleep 60 &
    local other_pid=$!
    mkdir -p "$PWT_DIR/jobs"
    cat >|"$PWT_DIR/jobs/SAME-NAME-server-1000000000.job" <<JOB
id=SAME-NAME-server-1000000000
pid=$other_pid
pgid=$other_pid
command=server
worktree=SAME-NAME
project=other-project
log=$PWT_DIR/other.log
started_at=2026-01-01T00:00:00Z
started_epoch=1000000000
status=running
JOB
    echo "other project log" >|"$PWT_DIR/other.log"

    run "$PWT_BIN" server SAME-NAME --bg
    [ "$status" -eq 0 ]
    case "$output" in *'"job_id"'*) ;; *) echo "server did not start: $output" >&2; kill "$other_pid"; return 1 ;; esac
    local own_id
    own_id=$(echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//')
    [ "$own_id" != "SAME-NAME-server-1000000000" ]

    # The duplicate guard still works inside the project
    run "$PWT_BIN" server SAME-NAME --bg
    [ "$status" -ne 0 ]
    case "$output" in *"Already running"*"$own_id"*) ;; *) echo "wrong duplicate: $output" >&2; kill "$other_pid"; return 1 ;; esac

    # logs and servers by name see this project's job, not the other one
    run "$PWT_BIN" logs SAME-NAME
    case "$output" in *"other project log"*) echo "logs picked the other project's job" >&2; kill "$other_pid"; return 1 ;; esac
    run "$PWT_BIN" servers
    case "$output" in *"job:$own_id"*) ;; *) echo "servers did not show own job: $output" >&2; kill "$other_pid"; return 1 ;; esac

    # stop by worktree name stops this project's job and leaves the other alive
    run "$PWT_BIN" servers stop SAME-NAME
    [ "$status" -eq 0 ]
    kill -0 "$other_pid"
    [ "$(sed -n 's/^status=//p' "$PWT_DIR/jobs/SAME-NAME-server-1000000000.job")" = "running" ]
    [ "$(sed -n 's/^status=//p' "$PWT_DIR/jobs/${own_id}.job")" = "stopped" ]

    kill "$other_pid" 2>/dev/null || true
}
