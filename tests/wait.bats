#!/usr/bin/env bats
# Tests for the blocking wait primitives:
#   pwt jobs wait <id-or-worktree> [--timeout <s>]
#   pwt server wait [worktree] [--log-contains <str>] [--timeout <s>]
# Exit codes: 0=ready/finished, 3=not found, 5=timeout

load test_helper

setup() {
    setup_test_env

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    # Randomized per-file base port (parallel bats files each use their own
    # 4xxxx range to avoid TCP port collisions)
    export TEST_BASE_PORT=$((45000 + RANDOM % 1000))
    mkdir -p "$TEST_WORKTREES"

    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
EOF

    cd "$TEST_REPO"
    echo "content" >file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    "$PWT_BIN" jobs stop --all >/dev/null 2>&1 || true
    # Kill any leftover job processes directly (belt and suspenders)
    if [ -d "$PWT_DIR/jobs" ]; then
        for job in "$PWT_DIR/jobs"/*.job; do
            [ -f "$job" ] || continue
            local pid
            pid=$(sed -n 's/^pid=//p' "$job" | head -1 || true)
            [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
        done
    fi
    if command -v lsof >/dev/null 2>&1 && [ -n "${TEST_BASE_PORT:-}" ]; then
        for port in $(seq "$TEST_BASE_PORT" "$((TEST_BASE_PORT + 10))"); do
            local pids
            pids=$(lsof -ti ":$port" 2>/dev/null || true)
            [ -n "$pids" ] && echo "$pids" | xargs kill -9 2>/dev/null || true
        done
    fi
    teardown_test_env
}

# Extract the job id from `pwt server --bg` output
job_id_from_output() {
    echo "$output" | grep -o '"job_id":"[^"]*"' | head -1 | sed 's/"job_id":"//;s/"//'
}

# ============================================
# pwt jobs wait
# ============================================

@test "pwt jobs wait returns when job finishes" {
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    sleep 1
}
EOF
    "$PWT_BIN" create TEST-WAIT-DONE HEAD

    cd "$TEST_WORKTREES/TEST-WAIT-DONE"
    run "$PWT_BIN" server --bg
    # Surface the launch output in the bats failure log (CI-only failures
    # are undebuggable without it: `run` swallows it otherwise)
    echo "server --bg output: $output"
    [ "$status" -eq 0 ]

    local job_id
    job_id=$(job_id_from_output)
    [ -n "$job_id" ]

    run "$PWT_BIN" jobs wait "$job_id" --timeout 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"$job_id"* ]]
    [[ "$output" == *"stopped"* ]]
}

@test "pwt jobs wait accepts a worktree name" {
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    sleep 1
}
EOF
    "$PWT_BIN" create TEST-WAIT-NAME HEAD

    cd "$TEST_WORKTREES/TEST-WAIT-NAME"
    run "$PWT_BIN" server --bg
    echo "server --bg output: $output"
    [ "$status" -eq 0 ]

    run "$PWT_BIN" jobs wait TEST-WAIT-NAME --timeout 10
    echo "jobs wait output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-WAIT-NAME"* ]]
    [[ "$output" == *"stopped"* ]]
}

@test "pwt jobs wait times out with exit 5" {
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    sleep 30
}
EOF
    "$PWT_BIN" create TEST-WAIT-TMOUT HEAD

    cd "$TEST_WORKTREES/TEST-WAIT-TMOUT"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    local job_id
    job_id=$(job_id_from_output)
    [ -n "$job_id" ]

    run "$PWT_BIN" jobs wait "$job_id" --timeout 1
    [ "$status" -eq 5 ]
    [[ "$output" == *"Timeout"* ]]

    "$PWT_BIN" jobs stop "$job_id" 2>/dev/null || true
}

@test "pwt jobs wait unknown job exits 3" {
    run "$PWT_BIN" jobs wait nonexistent-job-xyz --timeout 5
    [ "$status" -eq 3 ]
    [[ "$output" == *"not found"* ]]
}

@test "pwt jobs wait with no target shows usage (exit 2)" {
    run "$PWT_BIN" jobs wait
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt jobs wait rejects non-numeric timeout (exit 2)" {
    run "$PWT_BIN" jobs wait some-job --timeout abc
    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid --timeout"* ]]
}

# ============================================
# pwt server wait (port readiness)
# ============================================

@test "pwt server wait succeeds when port accepts connections" {
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    exec perl -MIO::Socket::INET -e '
        my $srv = IO::Socket::INET->new(
            LocalAddr => "127.0.0.1",
            LocalPort => $ENV{PWT_PORT},
            Listen    => 5,
            ReuseAddr => 1,
        ) or die "listen: $!";
        while (my $c = $srv->accept) { close $c; }
    '
}
EOF
    "$PWT_BIN" create TEST-WAIT-PORT HEAD

    cd "$TEST_WORKTREES/TEST-WAIT-PORT"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    run "$PWT_BIN" server wait TEST-WAIT-PORT --timeout 15
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ready"* ]]
    [[ "$output" == *"TEST-WAIT-PORT"* ]]
}

@test "pwt server wait times out when nothing listens (exit 5)" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-WAIT-NOSRV HEAD

    run "$PWT_BIN" server wait TEST-WAIT-NOSRV --timeout 1
    [ "$status" -eq 5 ]
    [[ "$output" == *"Timeout"* ]]
}

@test "pwt server wait exits 3 when worktree has no port" {
    # Worktree dir exists but was never registered by pwt (no metadata, no
    # legacy -NNNN port suffix in the name)
    mkdir -p "$TEST_WORKTREES/orphan-wt"

    cd "$TEST_REPO"
    run "$PWT_BIN" server wait orphan-wt --timeout 5
    [ "$status" -eq 3 ]
    [[ "$output" == *"No port allocated"* ]]
}

@test "pwt server wait unknown worktree exits 3" {
    cd "$TEST_REPO"
    run "$PWT_BIN" server wait nonexistent-wt-xyz --timeout 5
    [ "$status" -eq 3 ]
    [[ "$output" == *"not found"* ]]
}

# ============================================
# pwt server wait --log-contains
# ============================================

@test "pwt server wait --log-contains succeeds on log marker" {
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    echo "warming up"
    echo "SERVER_READY_MARKER"
    sleep 30
}
EOF
    "$PWT_BIN" create TEST-WAIT-LOG HEAD

    cd "$TEST_WORKTREES/TEST-WAIT-LOG"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    run "$PWT_BIN" server wait TEST-WAIT-LOG --log-contains "SERVER_READY_MARKER" --timeout 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ready"* ]]
}

@test "pwt server wait --log-contains times out when marker never appears" {
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    echo "starting"
    sleep 30
}
EOF
    "$PWT_BIN" create TEST-WAIT-LOGTMOUT HEAD

    cd "$TEST_WORKTREES/TEST-WAIT-LOGTMOUT"
    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]

    run "$PWT_BIN" server wait TEST-WAIT-LOGTMOUT --log-contains "NEVER_PRINTED" --timeout 1
    [ "$status" -eq 5 ]
    [[ "$output" == *"Timeout"* ]]
}

@test "pwt server wait --log-contains exits 3 without a server job" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-WAIT-NOJOB HEAD

    run "$PWT_BIN" server wait TEST-WAIT-NOJOB --log-contains "anything" --timeout 5
    [ "$status" -eq 3 ]
    [[ "$output" == *"No server job found"* ]]
}

# ============================================
# help
# ============================================

@test "pwt server wait --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" server wait --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pwt server wait"* ]]
    [[ "$output" == *"--log-contains"* ]]
    [[ "$output" == *"--timeout"* ]]
}

@test "pwt jobs help mentions wait" {
    run "$PWT_BIN" jobs help
    [ "$status" -eq 0 ]
    [[ "$output" == *"wait"* ]]
}
