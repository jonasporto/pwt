#!/usr/bin/env bats
# Tests for pwt gateway and servers commands

load test_helper

setup() {
    setup_test_env

    command -v node >/dev/null 2>&1 || skip "node is required for gateway tests"

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    export TEST_BASE_PORT=$((42000 + RANDOM % 1000))
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

@test "pwt gateway init configures project gateway port" {
    cd "$TEST_REPO"

    run "$PWT_BIN" gateway init --port "$TEST_GATEWAY_PORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gateway port set"* ]]

    run "$PWT_BIN" config gateway_port
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_GATEWAY_PORT" ]

    run "$PWT_BIN" gateway url
    [ "$status" -eq 0 ]
    [ "$output" = "http://localhost:$TEST_GATEWAY_PORT" ]
}

@test "pwt gateway init accepts custom public host" {
    cd "$TEST_REPO"

    run "$PWT_BIN" gateway init --port "$TEST_GATEWAY_PORT" --host "app.localhost"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gateway host set to app.localhost"* ]]

    run "$PWT_BIN" gateway url
    [ "$status" -eq 0 ]
    [ "$output" = "http://app.localhost:$TEST_GATEWAY_PORT" ]

    run "$PWT_BIN" gateway status --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.host')" = "app.localhost" ]
    [ "$(echo "$output" | jq -r '.url')" = "http://app.localhost:$TEST_GATEWAY_PORT" ]
}

@test "pwt gateway init rejects host with protocol" {
    cd "$TEST_REPO"

    run "$PWT_BIN" gateway init --port "$TEST_GATEWAY_PORT" --host "http://localhost"
    [ "$status" -ne 0 ]
    [[ "$output" == *"without protocol, port, or path"* ]]
}

@test "pwt gateway up --port starts project-scoped daemon and down stops it" {
    cd "$TEST_REPO"

    run "$PWT_BIN" gateway up --port "$TEST_GATEWAY_PORT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gateway running"* ]]

    run "$PWT_BIN" gateway status --json
    [ "$status" -eq 0 ]
    local running=$(echo "$output" | jq -r '.running')
    local port=$(echo "$output" | jq -r '.port')
    local url=$(echo "$output" | jq -r '.url')
    [ "$running" = "true" ]
    [ "$port" = "$TEST_GATEWAY_PORT" ]
    [ "$url" = "http://localhost:$TEST_GATEWAY_PORT" ]

    run "$PWT_BIN" gateway down
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gateway stopped"* ]]
}

@test "pwt gateway use auto-starts server and proxies to selected worktree" {
    cd "$TEST_REPO"
    write_http_server_pwtfile
    "$PWT_BIN" gateway up --port "$TEST_GATEWAY_PORT"
    "$PWT_BIN" create GATEWAY-A HEAD >/dev/null

    run env PWT_GATEWAY_WAIT_SECONDS=5 "$PWT_BIN" gateway use GATEWAY-A
    [ "$status" -eq 0 ]
    [[ "$output" == *"Gateway target: GATEWAY-A"* ]]
    [[ "$output" == *"Gateway URL:"* ]]

    run http_get_gateway "$TEST_GATEWAY_PORT"
    [ "$status" -eq 0 ]
    [ "$output" = "GATEWAY-A" ]

    run "$PWT_BIN" gateway status --json
    [ "$status" -eq 0 ]
    local target=$(echo "$output" | jq -r '.target')
    [ "$target" = "GATEWAY-A" ]
}

# ============================================
# Port validation (A9): shipped in August with zero tests
# ============================================

@test "gateway init without a port is a usage error" {
    cd "$TEST_REPO"
    run -2 "$PWT_BIN" gateway init
    [[ "$output" == *"--port"* ]]
}

@test "gateway init rejects a non-numeric port" {
    cd "$TEST_REPO"
    run -2 "$PWT_BIN" gateway init --port abc
    [[ "$output" == *"port"* ]]
    # And nothing may have been persisted
    run grep -c "gateway_port" "$PWT_DIR/projects/test-project/config"
    [[ "$output" == "0" ]] || [ "$status" -ne 0 ]
}

@test "gateway init rejects a port outside 1-65535" {
    cd "$TEST_REPO"
    run -2 "$PWT_BIN" gateway init --port 0
    run -2 "$PWT_BIN" gateway init --port 70000
    [[ "$output" == *"1-65535"* ]] || {
        echo "expected the valid range in the message, got: $output" >&2
        return 1
    }
}

@test "gateway init persists a valid port" {
    cd "$TEST_REPO"
    run "$PWT_BIN" gateway init --port 45123
    assert_success
    grep -q "gateway_port=45123" "$PWT_DIR/projects/test-project/config"
}
