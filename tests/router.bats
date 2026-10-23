#!/usr/bin/env bats
# pwt router: stable public ports, wake on request, idle stop, server cap.

load test_helper

setup() {
    setup_test_env

    command -v node >/dev/null 2>&1 || skip "node is required for router tests"

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    # 47000-47499: own range (gateway.bats 42xxx ... wait.bats 46xxx).
    # Public ports sit at +200, the router's own port at +400.
    export TEST_BASE_PORT=$((47000 + (RANDOM % 9) * 50))
    export TEST_ROUTER_PORT=$((TEST_BASE_PORT + 400))
    mkdir -p "$TEST_WORKTREES"

    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
EOF
    printf 'router.port=%s\nrouter.port_offset=200\nrouter.listen=127.0.0.1\n' \
        "$TEST_ROUTER_PORT" >"$PWT_DIR/config"
    # The router asks for routes and idleness on these clocks
    export PWT_ROUTER_REFRESH_MS=500
    export PWT_ROUTER_IDLE_TICK_MS=300

    cd "$TEST_REPO"
    write_server_pwtfile
}

teardown() {
    "$PWT_BIN" router down >/dev/null 2>&1 || true
    "$PWT_BIN" jobs stop --all >/dev/null 2>&1 || true
    # Listeners only, and only in this file's range: an unfiltered lsof
    # matches clients too (see helpers.bats)
    # (one snapshot, filtered by port: a per-port lsof costs ~0.3 s each)
    if command -v lsof >/dev/null 2>&1 && [ -n "${TEST_BASE_PORT:-}" ]; then
        local pids
        pids=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null |
            awk -v lo="$TEST_BASE_PORT" -v hi="$((TEST_BASE_PORT + 449))" \
                'NR > 1 { n = split($9, a, ":"); p = a[n] + 0; if (p >= lo && p <= hi) print $2 }' | sort -u)
        [ -n "$pids" ] && echo "$pids" | xargs kill -9 2>/dev/null || true
    fi
    teardown_test_env
}

# A server that answers with what it saw, upgrades websockets and echoes;
# a .crash file makes it fail its boot, a .slow file makes it boot slowly
write_server_pwtfile() {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() {
    pwt_step deps sleep 0.2
    [ -f "$MAIN_APP/.crash" ] && { echo "boom: missing dependency"; return 3; }
    [ -f "$MAIN_APP/.slow" ] && sleep 3
    exec node -e '
const http = require("http");
const s = http.createServer((req, res) => {
  if (req.url === "/slow") { setTimeout(() => res.end("slow\n"), 1500); return; }
  res.setHeader("content-type", "text/plain");
  res.end([process.env.PWT_WORKTREE, req.headers["x-forwarded-for"], req.headers["x-forwarded-host"],
           req.headers["x-forwarded-proto"], req.headers["x-forwarded-port"]].join("|") + "\n");
});
s.on("upgrade", (req, sock) => {
  sock.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n");
  sock.on("data", (d) => sock.write(d));
});
s.listen(Number(process.env.PWT_PORT), "127.0.0.1");
'
}
longtask() { sleep 30; }
EOF
}

# GET through node (no curl on minimal images). Prints "<status> <body>".
http_get() {
    local port="$1" path="${2:-/}" accept="${3:-*/*}"
    node -e '
const http = require("http");
const [port, path, accept] = process.argv.slice(1);
http.get({host: "127.0.0.1", port: Number(port), path, headers: {accept}}, (res) => {
  let body = "";
  res.on("data", (c) => body += c);
  res.on("end", () => process.stdout.write(res.statusCode + " " + body));
}).on("error", (e) => { console.error(e.message); process.exit(1); });
' "$port" "$path" "$accept"
}

listening() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

start_router() {
    run "$PWT_BIN" router up
    [ "$status" -eq 0 ] || {
        echo "$output"
        cat "$PWT_DIR/router/router.log" 2>/dev/null
        return 1
    }
}

@test "router routes: every worktree and the main app, public port = port + offset" {
    "$PWT_BIN" create ROUTE-A HEAD >/dev/null
    local port
    port=$(state_get_port ROUTE-A)

    run "$PWT_BIN" router routes --porcelain
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\ttest-project\t@\t'"$TEST_BASE_PORT"$'\t\t\t'"$((TEST_BASE_PORT + 200))"* ]]
    [[ "$output" == *$'\ttest-project\tROUTE-A\t'"$port"$'\t\t\t'"$((port + 200))"* ]]

    run "$PWT_BIN" router routes --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"worktree":"ROUTE-A","port":'"$port"',"public_port":'"$((port + 200))"* ]]
    [[ "$output" == *'"public_url":"http://localhost:'"$((port + 200))"'"'* ]]
}

state_get_port() {
    sed -n 's/^port=//p' "$PWT_DIR/state/test-project/$1.meta"
}

@test "router url prints the stable public URL" {
    "$PWT_BIN" create ROUTE-URL HEAD >/dev/null
    local port
    port=$(state_get_port ROUTE-URL)
    run "$PWT_BIN" router url ROUTE-URL
    [ "$status" -eq 0 ]
    [ "$output" = "http://localhost:$((port + 200))" ]
}

@test "router config validates keys and values, --unset restores the default" {
    run "$PWT_BIN" router config nope 1
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown router setting: nope"* ]]

    run "$PWT_BIN" router config max_servers two
    [ "$status" -eq 2 ]

    run "$PWT_BIN" router config host_routing maybe
    [ "$status" -eq 2 ]

    run "$PWT_BIN" router config max_servers 3
    [ "$status" -eq 0 ]
    run "$PWT_BIN" router config max_servers
    [ "$output" = "3" ]

    run "$PWT_BIN" router config max_servers --unset
    [ "$status" -eq 0 ]
    run "$PWT_BIN" router config max_servers
    [ "$output" = "0" ]
}

@test "PWT_PUBLIC_PORT and PWT_PUBLIC_URL are always defined (set -u Pwtfile)" {
    "$PWT_BIN" create ROUTE-VARS HEAD >/dev/null
    cat >>"$TEST_REPO/Pwtfile" <<'EOF'
showvars() {
    set -u
    echo "public=$PWT_PUBLIC_PORT url=$PWT_PUBLIC_URL host=[$PWT_HOST] hosts=[$PWT_HOSTS]"
}
EOF
    local port
    port=$(state_get_port ROUTE-VARS)
    run "$PWT_BIN" test-project ROUTE-VARS showvars
    [ "$status" -eq 0 ]
    [[ "$output" == *"public=$((port + 200)) url=http://localhost:$((port + 200)) host=[] hosts=[]"* ]]
}

@test "a request to a stopped server wakes it and is answered, with X-Forwarded-*" {
    "$PWT_BIN" create WAKE-API HEAD >/dev/null
    local port pub
    port=$(state_get_port WAKE-API)
    pub=$((port + 200))
    start_router
    ! listening "$port"

    run http_get "$pub" /
    [ "$status" -eq 0 ]
    [[ "$output" == "200 WAKE-API|127.0.0.1|127.0.0.1:$pub|http|$pub"* ]]
    listening "$port"
    grep -q "wake test-project/WAKE-API" "$PWT_DIR/router/router.log"
}

@test "a browser gets the starting page, then /__pwt/boot reports the steps" {
    "$PWT_BIN" create WAKE-HTML HEAD >/dev/null
    local pub
    pub=$(($(state_get_port WAKE-HTML) + 200))
    start_router

    run http_get "$pub" / "text/html,application/xhtml+xml"
    [ "$status" -eq 0 ]
    [[ "$output" == "503 "* ]]
    [[ "$output" == *"Starting test-project / WAKE-HTML"* ]]
    [[ "$output" == *"/__pwt/boot"* ]]

    wait_for "http_get $pub /__pwt/boot | grep -q '\"state\":\"ready\"'" 20
    run http_get "$pub" /__pwt/boot
    [[ "$output" == *'"step":"deps","state":"done"'* ]]
    [[ "$output" == *'"step":"listen","state":"done"'* ]]
}

@test "the second boot carries an ETA per step from the last good boot" {
    "$PWT_BIN" create WAKE-ETA HEAD >/dev/null
    local pub
    pub=$(($(state_get_port WAKE-ETA) + 200))
    run "$PWT_BIN" server WAKE-ETA --bg --progress json
    [ "$status" -eq 0 ]
    "$PWT_BIN" servers stop WAKE-ETA >/dev/null
    touch "$TEST_REPO/.slow"
    start_router

    run http_get "$pub" / "text/html"
    [[ "$output" == "503 "* ]]
    wait_for "http_get $pub /__pwt/boot | grep -q '\"state\":\"booting\"'" 10
    run http_get "$pub" /__pwt/boot
    [[ "$output" =~ \"eta_ms\":[0-9]+ ]]
    [[ "$output" =~ \"step\":\"deps\",\"state\":\"[a-z]+\",\"duration_ms\":[0-9a-z]+,\"eta_ms\":[0-9]+ ]]
}

@test "a failed boot reports the error and the log tail" {
    "$PWT_BIN" create WAKE-FAIL HEAD >/dev/null
    local pub
    pub=$(($(state_get_port WAKE-FAIL) + 200))
    touch "$TEST_REPO/.crash"
    start_router

    run http_get "$pub" /api
    [[ "$output" == "503 "* ]]
    [[ "$output" == *"failed to start"* ]]

    run http_get "$pub" /__pwt/boot
    [[ "$output" == *'"state":"failed"'* ]]
    [[ "$output" == *"boom: missing dependency"* ]]
}

@test "the failure page hides the log tail with expose_logs false" {
    "$PWT_BIN" create WAKE-NOLOG HEAD >/dev/null
    local pub
    pub=$(($(state_get_port WAKE-NOLOG) + 200))
    touch "$TEST_REPO/.crash"
    "$PWT_BIN" router config expose_logs false >/dev/null
    start_router

    http_get "$pub" /api >/dev/null || true
    run http_get "$pub" /__pwt/boot
    [[ "$output" == *'"state":"failed"'* ]]
    [[ "$output" != *"boom: missing dependency"* ]]
}

@test "a websocket upgrade wakes the server and passes through" {
    "$PWT_BIN" create WAKE-WS HEAD >/dev/null
    local pub
    pub=$(($(state_get_port WAKE-WS) + 200))
    start_router

    run node -e '
const net = require("net");
const s = net.connect(Number(process.argv[1]), "127.0.0.1", () =>
  s.write("GET /cable HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"));
let buf = "";
s.on("data", (d) => {
  buf += d;
  if (buf.includes("\r\n\r\n") && !buf.includes("PING")) s.write("PING");
  else if (buf.includes("PING")) { console.log(buf.split("\r\n")[0] + " echo"); process.exit(0); }
});
s.on("error", (e) => { console.error(e.message); process.exit(1); });
setTimeout(() => { console.error("timeout: " + buf); process.exit(1); }, 20000);
' "$pub"
    [ "$status" -eq 0 ]
    [[ "$output" == "HTTP/1.1 101 Switching Protocols echo" ]]
}

@test "idle stop stops a routed server and leaves an unrouted one alone" {
    "$PWT_BIN" create IDLE-ROUTED HEAD >/dev/null
    "$PWT_BIN" create IDLE-DIRECT HEAD >/dev/null
    local routed direct
    routed=$(state_get_port IDLE-ROUTED)
    direct=$(state_get_port IDLE-DIRECT)
    "$PWT_BIN" router config idle_minutes 0.02 >/dev/null # ~1.2 s
    "$PWT_BIN" server IDLE-DIRECT --bg --progress json >/dev/null
    start_router

    run http_get "$((routed + 200))" /
    [[ "$output" == "200 "* ]]
    wait_for "! listening $routed" 15
    wait_for "grep -q 'idle stop test-project/IDLE-ROUTED' '$PWT_DIR/router/router.log'" 5
    listening "$direct"
    grep -q $'\tserver_idle_stop\t' "$PWT_DIR/events.log"
}

@test "idle stop waits for a request in flight" {
    "$PWT_BIN" create IDLE-BUSY HEAD >/dev/null
    local port
    port=$(state_get_port IDLE-BUSY)
    "$PWT_BIN" router config idle_minutes 0.01 >/dev/null # ~0.6 s
    start_router
    http_get "$((port + 200))" / >/dev/null

    # /slow takes 1.5 s; the idle window passes while it is in flight
    run http_get "$((port + 200))" /slow
    [ "$output" = "200 slow" ]
}

@test "servers stop --idle refuses while another pwt job runs for the worktree" {
    "$PWT_BIN" create STOP-BUSY HEAD >/dev/null
    "$PWT_BIN" server STOP-BUSY --bg --progress json >/dev/null
    "$PWT_BIN" --bg test-project STOP-BUSY longtask >/dev/null

    run "$PWT_BIN" servers stop STOP-BUSY --idle
    [ "$status" -eq 4 ]
    [[ "$output" == *"Busy"* ]]
    listening "$(state_get_port STOP-BUSY)"

    run "$PWT_BIN" servers stop STOP-BUSY
    [ "$status" -eq 0 ]
    wait_for "! listening $(state_get_port STOP-BUSY)" 5
}

@test "servers stop exits 3 when pwt runs no server for the worktree" {
    "$PWT_BIN" create STOP-NONE HEAD >/dev/null
    run "$PWT_BIN" servers stop STOP-NONE
    [ "$status" -eq 3 ]
    [[ "$output" == *"No pwt-managed server running for STOP-NONE"* ]]
}

@test "max_servers evicts the least recently used idle server" {
    "$PWT_BIN" create CAP-OLD HEAD >/dev/null
    "$PWT_BIN" create CAP-NEW HEAD >/dev/null
    "$PWT_BIN" create CAP-THIRD HEAD >/dev/null
    "$PWT_BIN" router config max_servers 2 >/dev/null
    "$PWT_BIN" server CAP-OLD --bg --progress json >/dev/null
    sleep 1 # started_epoch has whole-second resolution
    "$PWT_BIN" server CAP-NEW --bg --progress json >/dev/null

    run "$PWT_BIN" server CAP-THIRD --bg --progress json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"step":"boot","state":"done"'* ]]
    wait_for "! listening $(state_get_port CAP-OLD)" 5
    listening "$(state_get_port CAP-NEW)"
    listening "$(state_get_port CAP-THIRD)"
    grep -q $'CAP-OLD\tserver_evicted\t' "$PWT_DIR/events.log"
}

@test "max_servers refuses (exit 4) when every running server is busy" {
    "$PWT_BIN" create CAP-BUSY HEAD >/dev/null
    "$PWT_BIN" create CAP-WANT HEAD >/dev/null
    "$PWT_BIN" router config max_servers 1 >/dev/null
    "$PWT_BIN" server CAP-BUSY --bg --progress json >/dev/null
    "$PWT_BIN" --bg test-project CAP-BUSY longtask >/dev/null

    run "$PWT_BIN" server CAP-WANT --bg
    [ "$status" -eq 4 ]
    [[ "$output" == *"server cap reached (1 of 1 running, none idle)"* ]]
    listening "$(state_get_port CAP-BUSY)"
}

@test "the main app is neither counted by the cap nor evicted" {
    "$PWT_BIN" create CAP-ONLY HEAD >/dev/null
    "$PWT_BIN" router config max_servers 1 >/dev/null
    "$PWT_BIN" server @ --bg --progress json >/dev/null
    listening "$TEST_BASE_PORT"

    run "$PWT_BIN" server CAP-ONLY --bg --progress json
    [ "$status" -eq 0 ]
    listening "$TEST_BASE_PORT"
}

@test "router status --json reports the policy" {
    "$PWT_BIN" router config max_servers 2 >/dev/null
    run "$PWT_BIN" router status --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"running":false'* ]]
    [[ "$output" == *'"port_offset":200'* ]]
    [[ "$output" == *'"max_servers":2'* ]]
    [[ "$output" == *'"idle_minutes":"30"'* ]]
}

@test "router up refuses a port another process holds" {
    node -e 'require("net").createServer().listen(Number(process.argv[1]), "127.0.0.1")' "$TEST_ROUTER_PORT" &
    local holder=$!
    wait_for "listening $TEST_ROUTER_PORT" 5
    run "$PWT_BIN" router up
    kill "$holder" 2>/dev/null || true
    [ "$status" -eq 4 ]
    [[ "$output" == *"already in use"* ]]
}

@test "host routing (opt-in) routes <worktree>.<project>.localhost and hosts() aliases" {
    "$PWT_BIN" create HOST-A HEAD >/dev/null
    cat >>"$TEST_REPO/Pwtfile" <<'EOF'
hosts() { echo api; echo '*'; }
EOF
    "$PWT_BIN" router config host_routing true >/dev/null
    run "$PWT_BIN" router routes --porcelain
    [[ "$output" == *"host-a.test-project.localhost"$'\t'* ]]
    [[ "$output" == *"api.host-a.test-project.localhost"$'\t'*$'\tapi\tPWT_HOST_API\t'* ]]
    [[ "$output" == *"*.host-a.test-project.localhost"$'\t'* ]]

    start_router
    run node -e '
const http = require("http");
http.get({host: "127.0.0.1", port: Number(process.argv[1]), path: "/", headers: {host: "tenant1.host-a.test-project.localhost"}}, (res) => {
  let b = ""; res.on("data", (c) => b += c); res.on("end", () => process.stdout.write(res.statusCode + " " + b));
}).on("error", (e) => { console.error(e.message); process.exit(1); });
' "$TEST_ROUTER_PORT"
    [[ "$output" == "200 HOST-A|"* ]]
}
