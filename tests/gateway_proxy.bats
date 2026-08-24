#!/usr/bin/env bats
# Tests for gateway target switching, servers reporting, and multi-project
# isolation. Split from gateway.bats: that file was the slowest of the suite
# (~95s) and the per-file parallel harness's wall clock is bounded by its
# slowest file.

load test_helper

setup() {
    setup_test_env

    command -v node >/dev/null 2>&1 || skip "node is required for gateway tests"

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    # 45xxx: own range so a parallel run never collides with gateway.bats
    # (42xxx), audit_fixes (43xxx), or create_remove (44xxx)
    export TEST_BASE_PORT=$((45000 + RANDOM % 1000))
    export TEST_GATEWAY_PORT=$((TEST_BASE_PORT + 50))
    mkdir -p "$TEST_WORKTREES"

    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
alias=tp
EOF

    cd "$TEST_REPO"
    echo "content" >file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    "$PWT_BIN" test-project gateway stop >/dev/null 2>&1 || true
    "$PWT_BIN" other-project gateway stop >/dev/null 2>&1 || true
    "$PWT_BIN" jobs stop --all >/dev/null 2>&1 || true
    if command -v lsof >/dev/null 2>&1 && [ -n "${TEST_BASE_PORT:-}" ]; then
        for port in $(seq "$TEST_BASE_PORT" "$((TEST_BASE_PORT + 80))"); do
            local pids
            pids=$(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null || true)
            [ -n "$pids" ] && echo "$pids" | xargs kill -9 2>/dev/null || true
        done
    fi
    teardown_test_env
}

write_http_server_pwtfile() {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    node -e '
const http = require("http");
const body = process.env.PWT_WORKTREE || "";
const port = Number(process.env.PWT_PORT);
http.createServer((_req, res) => {
  res.writeHead(200, {"content-type": "text/plain"});
  res.end(body + "\n");
}).listen(port, "127.0.0.1");
'
}
EOF
    git add Pwtfile
    git commit -q -m "Add Pwtfile server"
}

http_get_gateway() {
    local port="$1"
    node -e '
const http = require("http");
const port = Number(process.argv[1]);
http.get({host: "127.0.0.1", port, path: "/"}, (res) => {
  let body = "";
  res.on("data", chunk => body += chunk);
  res.on("end", () => process.stdout.write(body));
}).on("error", err => {
  console.error(err.message);
  process.exit(1);
});
' "$port"
}

@test "pwt gateway use switches new requests to the new target" {
    cd "$TEST_REPO"
    write_http_server_pwtfile
    "$PWT_BIN" gateway up --port "$TEST_GATEWAY_PORT"
    "$PWT_BIN" create GATEWAY-A HEAD >/dev/null
    "$PWT_BIN" create GATEWAY-B HEAD >/dev/null

    env PWT_GATEWAY_WAIT_SECONDS=5 "$PWT_BIN" gateway use GATEWAY-A >/dev/null
    run http_get_gateway "$TEST_GATEWAY_PORT"
    [ "$status" -eq 0 ]
    [ "$output" = "GATEWAY-A" ]

    env PWT_GATEWAY_WAIT_SECONDS=5 "$PWT_BIN" gateway use GATEWAY-B >/dev/null
    run http_get_gateway "$TEST_GATEWAY_PORT"
    [ "$status" -eq 0 ]
    [ "$output" = "GATEWAY-B" ]
}

@test "pwt gateway use fails for stopped target without Pwtfile server" {
    cd "$TEST_REPO"
    "$PWT_BIN" gateway up --port "$TEST_GATEWAY_PORT"
    "$PWT_BIN" create GATEWAY-NO-SERVER HEAD >/dev/null

    run "$PWT_BIN" gateway use GATEWAY-NO-SERVER
    [ "$status" -ne 0 ]
    [[ "$output" == *"no Pwtfile server command"* ]]
}

@test "pwt servers reports gateway and all worktrees generically" {
    cd "$TEST_REPO"
    "$PWT_BIN" gateway up --port "$TEST_GATEWAY_PORT"
    "$PWT_BIN" create GATEWAY-LIST HEAD >/dev/null

    run "$PWT_BIN" servers --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Servers (test-project)"* ]]
    [[ "$output" == *"Gateway:"* ]]
    [[ "$output" == *"Pwtfile server: not configured"* ]]
    [[ "$output" == *"GATEWAY-LIST"* ]]
}

@test "pwt <project> servers works from outside project" {
    cd "$TEST_REPO"
    "$PWT_BIN" gateway up --port "$TEST_GATEWAY_PORT"
    "$PWT_BIN" create GATEWAY-PROJECT HEAD >/dev/null

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project servers --json
    [ "$status" -eq 0 ]
    local project=$(echo "$output" | jq -r '.project')
    [ "$project" = "test-project" ]
}

@test "pwt <project> gateway down stops only that project's gateway" {
    local other_repo="$TEST_TEMP_DIR/other-repo"
    local other_worktrees="$TEST_TEMP_DIR/other-worktrees"
    local other_gateway_port=$((TEST_GATEWAY_PORT + 1))

    mkdir -p "$other_repo" "$other_worktrees"
    git -C "$other_repo" init -q
    git -C "$other_repo" config user.email "test@test.com"
    git -C "$other_repo" config user.name "Test User"
    echo "other" >"$other_repo/file.txt"
    git -C "$other_repo" add file.txt
    git -C "$other_repo" commit -q -m "Initial commit"

    mkdir -p "$PWT_DIR/projects/other-project"
    cat >"$PWT_DIR/projects/other-project/config" <<EOF
path=$other_repo
worktrees_dir=$other_worktrees
branch_prefix=other/
base_port=$((TEST_BASE_PORT + 20))
EOF

    run "$PWT_BIN" test-project gateway up --port "$TEST_GATEWAY_PORT"
    [ "$status" -eq 0 ]

    run "$PWT_BIN" other-project gateway up --port "$other_gateway_port"
    [ "$status" -eq 0 ]

    run "$PWT_BIN" test-project gateway down
    [ "$status" -eq 0 ]

    run "$PWT_BIN" test-project gateway status --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.running')" = "false" ]

    run "$PWT_BIN" other-project gateway status --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.running')" = "true" ]
}
