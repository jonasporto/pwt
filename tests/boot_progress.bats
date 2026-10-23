#!/usr/bin/env bats
# Server boot progress: boot.jsonl, pwt_step, --progress json, and the
# process-group stop that a server ending in `exec` depends on.

load test_helper
bats_require_minimum_version 1.5.0

setup() {
    setup_test_env

    command -v node >/dev/null 2>&1 || skip "node is required for boot progress tests"

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    # 47500-47999: own range (router.bats has 47000-47499)
    export TEST_BASE_PORT=$((47500 + (RANDOM % 9) * 50))
    mkdir -p "$TEST_WORKTREES"
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
EOF
    cd "$TEST_REPO"
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    set -u
    pwt_step deps true
    pwt_step assets --skip "nothing changed"
    [ -f "$MAIN_APP/.fail-step" ] && { pwt_step migrate false || return 7; }
    [ -f "$MAIN_APP/.no-listen" ] && { echo "exiting early"; return 0; }
    exec node -e 'require("http").createServer((q, r) => r.end("ok")).listen(Number(process.env.PWT_PORT), "127.0.0.1")'
}
outside() { pwt_step anything echo "ran without a boot"; }
EOF
    "$PWT_BIN" create BOOT HEAD >/dev/null
    export BOOT_PORT
    BOOT_PORT=$(sed -n 's/^port=//p' "$PWT_DIR/state/test-project/BOOT.meta")
    export BOOT_FILE="$PWT_DIR/state/test-project/BOOT.boot.jsonl"
}

teardown() {
    "$PWT_BIN" jobs stop --all >/dev/null 2>&1 || true
    kill_test_jobs
    if command -v lsof >/dev/null 2>&1 && [ -n "${TEST_BASE_PORT:-}" ]; then
        local pids
        pids=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null |
            awk -v lo="$TEST_BASE_PORT" -v hi="$((TEST_BASE_PORT + 49))" \
                'NR > 1 { n = split($9, a, ":"); p = a[n] + 0; if (p >= lo && p <= hi) print $2 }' | sort -u)
        [ -n "$pids" ] && echo "$pids" | xargs kill -9 2>/dev/null || true
    fi
    teardown_test_env
}

listening() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

@test "server --bg --progress json streams the boot as JSON lines and exits 0 when listening" {
    run --separate-stderr "$PWT_BIN" server BOOT --bg --progress json
    [ "$status" -eq 0 ]
    # stdout is nothing but JSON lines
    while IFS= read -r line; do
        [[ "$line" == '{"ts":"'*'}' ]] || {
            echo "not a JSON line: $line"
            return 1
        }
    done <<<"$output"
    [[ "${lines[0]}" == *'"step":"boot","state":"start"'* ]]
    [[ "$output" == *'"step":"spawn","state":"done"'*'job='* ]]
    [[ "$output" == *'"step":"deps","state":"done","duration_ms":'[0-9]* ]]
    [[ "$output" == *'"step":"assets","state":"skip","duration_ms":null,"detail":"nothing changed"'* ]]
    [[ "$output" == *'"step":"listen","state":"done"'* ]]
    [[ "${lines[${#lines[@]} - 1]}" == *'"step":"boot","state":"done","duration_ms":'[0-9]* ]]
    listening "$BOOT_PORT"
    [ "$(grep -c . "$BOOT_FILE")" -eq "${#lines[@]}" ]
}

@test "a failing pwt_step records fail and --progress json exits 1" {
    touch "$TEST_REPO/.fail-step"
    run --separate-stderr "$PWT_BIN" server BOOT --bg --progress json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"step":"migrate","state":"fail"'*'"detail":"exit 1"'* ]]
    [[ "$output" == *'"step":"boot","state":"fail"'* ]]
}

@test "a server that exits before listening is a failed boot" {
    touch "$TEST_REPO/.no-listen"
    run --separate-stderr "$PWT_BIN" server BOOT --bg --progress json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"step":"boot","state":"fail"'* ]]
}

@test "--progress json without --bg is a usage error" {
    run "$PWT_BIN" server BOOT --progress json
    [ "$status" -eq 2 ]
    [[ "$output" == *"--progress json needs --bg"* ]]
}

@test "--progress takes only json" {
    run "$PWT_BIN" server BOOT --bg --progress yaml
    [ "$status" -eq 2 ]
}

@test "the last good boot is kept as boot.prev.jsonl; a failed one does not replace it" {
    "$PWT_BIN" server BOOT --bg --progress json >/dev/null 2>&1
    "$PWT_BIN" servers stop BOOT >/dev/null
    local first
    first=$(grep '"step":"boot","state":"done"' "$BOOT_FILE")

    touch "$TEST_REPO/.fail-step"
    run "$PWT_BIN" server BOOT --bg --progress json
    [ "$status" -eq 1 ]
    rm "$TEST_REPO/.fail-step"

    run "$PWT_BIN" server BOOT --bg --progress json
    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    # prev = the first good boot, not the failed one in between
    grep -qF "$first" "$PWT_DIR/state/test-project/BOOT.boot.prev.jsonl"
    ! grep -q '"state":"fail"' "$PWT_DIR/state/test-project/BOOT.boot.prev.jsonl"
}

@test "a foreground server writes its boot too" {
    "$PWT_BIN" server BOOT >/dev/null 2>&1 &
    local fg=$!
    wait_for "grep -q '\"step\":\"boot\",\"state\":\"done\"' '$BOOT_FILE'" 15
    kill_tree "$fg"
    grep -q '"step":"listen","state":"done"' "$BOOT_FILE"
}

@test "servers --json carries the boot summary and the public port" {
    "$PWT_BIN" server BOOT --bg --progress json >/dev/null 2>&1
    run "$PWT_BIN" servers --json
    [ "$status" -eq 0 ]
    [[ "$output" =~ \"boot\":\{\"state\":\"done\",\"duration_ms\":[0-9]+,\"last_good_ms\":[0-9]+\} ]]
    [[ "$output" == *'"public_port":'"$((BOOT_PORT + 10000))"* ]]
}

@test "pwt_step outside a boot just runs the command" {
    run "$PWT_BIN" test-project BOOT outside
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran without a boot"* ]]
}

@test "PWT_BOOT_FILE, PWT_CHANGED_FILES and PWT_PREVIOUS_COMMIT are always defined (set -u)" {
    cat >>"$TEST_REPO/Pwtfile" <<'EOF'
vars() { set -u; echo "boot=[$PWT_BOOT_FILE] changed=[$PWT_CHANGED_FILES] prev=[$PWT_PREVIOUS_COMMIT]"; }
EOF
    run "$PWT_BIN" test-project BOOT vars
    [ "$status" -eq 0 ]
    [[ "$output" == *"boot=[] changed=[] prev=[]"* ]]
}

@test "jobs stop kills the server a job execs into (its process group)" {
    "$PWT_BIN" server BOOT --bg --progress json >/dev/null 2>&1
    listening "$BOOT_PORT"
    run "$PWT_BIN" jobs stop --all
    [ "$status" -eq 0 ]
    wait_for "! listening $BOOT_PORT" 5
}

@test "without perl, --bg still detaches and stop still kills the server" {
    run --separate-stderr env PWT_NO_PERL=1 "$PWT_BIN" server BOOT --bg --progress json
    [ "$status" -eq 0 ]
    listening "$BOOT_PORT"
    run "$PWT_BIN" jobs stop --all
    [ "$status" -eq 0 ]
    wait_for "! listening $BOOT_PORT" 5
}
