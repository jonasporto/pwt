#!/usr/bin/env bats
# A port held by a macOS system daemon is not "your server running".
#
# AirPlay Receiver (ControlCenter) binds 5000 and 7000 by default, which is
# exactly where Flask, Rails and every "base port" convention start. Every
# place that reports occupancy has to tell the two apart, not just the one
# that happened to grow the check first.

load test_helper

setup() {
    setup_test_env
    STUB_BIN="$TEST_TEMP_DIR/stub-bin"
    mkdir -p "$STUB_BIN"
}

teardown() {
    teardown_test_env
}

# lsof stub: <port> is held by <pid>, running <command line>
_stub_lsof() {
    local port="$1" pid="$2" cmd="$3"
    cat >"$STUB_BIN/lsof" <<EOF
#!/usr/bin/env bash
case "\$*" in
*-iTCP*)
    echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
    echo "${cmd##*/} $pid root 30u IPv4 0x1 0t0 TCP *:$port (LISTEN)"
    ;;
*:$port*) echo "$pid" ;;
*) exit 1 ;;
esac
EOF
    chmod +x "$STUB_BIN/lsof"
}

# ps stub: <pid> reports <command line>; anything else hits the real ps.
# Both output formats pwt asks for have to be emulated, or the classifier
# reads a command line as a pid and silently sees nothing.
_stub_ps() {
    local pid="$1" cmd="$2"
    cat >"$STUB_BIN/ps" <<EOF
#!/usr/bin/env bash
case "\$*" in
*" $pid"*)
    case "\$*" in
    *pid=,command=*) printf '%5s %s\n' "$pid" "$cmd" ;;
    *) echo "$cmd" ;;
    esac
    ;;
*) exec /bin/ps "\$@" ;;
esac
EOF
    chmod +x "$STUB_BIN/ps"
}

CONTROL_CENTER=/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter

# ============================================
# Classifying one process
# ============================================

@test "port_pid_is_system recognises ControlCenter by its system path" {
    source_pwt_functions port_pid_is_system
    _stub_ps 4242 "$CONTROL_CENTER"
    PATH="$STUB_BIN:$PATH" run port_pid_is_system 4242
    assert_success "ControlCenter must classify as a system daemon"
}

@test "port_pid_is_system leaves a dev server alone" {
    source_pwt_functions port_pid_is_system
    _stub_ps 4242 "puma 6.4.0 (tcp://0.0.0.0:5000) [app]"
    PATH="$STUB_BIN:$PATH" run port_pid_is_system 4242
    [ "$status" -ne 127 ] # a missing function is not a passing test
    assert_failure "a dev server must never be filtered out as system noise"
}

@test "port_pid_is_system recognises a /usr/libexec daemon" {
    source_pwt_functions port_pid_is_system
    _stub_ps 4242 "/usr/libexec/rapportd"
    PATH="$STUB_BIN:$PATH" run port_pid_is_system 4242
    assert_success
}

@test "port_pid_is_system says no when the pid is gone" {
    source_pwt_functions port_pid_is_system
    run port_pid_is_system 999999
    [ "$status" -ne 127 ]
    assert_failure
}

@test "port_is_system requires every listener on the port to be system" {
    source_pwt_functions has_lsof get_pids_on_port port_pid_is_system port_is_system

    cat >"$STUB_BIN/lsof" <<'EOF'
#!/usr/bin/env bash
echo 4242
echo 4243
EOF
    chmod +x "$STUB_BIN/lsof"
    cat >"$STUB_BIN/ps" <<EOF
#!/usr/bin/env bash
case "\$*" in
*4242*) echo "$CONTROL_CENTER" ;;
*4243*) echo "puma 6.4.0" ;;
*) exec /bin/ps "\$@" ;;
esac
EOF
    chmod +x "$STUB_BIN/ps"

    PATH="$STUB_BIN:$PATH" run port_is_system 5000
    [ "$status" -ne 127 ]
    assert_failure "a real server sharing the port means the port is in use"
}

# ============================================
# What the commands report
# ============================================

_project_on_port() {
    local port="$1"
    mkdir -p "$PWT_DIR/projects/app" "$TEST_TEMP_DIR/wts/feat" "$PWT_DIR/state/app"
    git init -q -b main "$TEST_TEMP_DIR/app"
    git -C "$TEST_TEMP_DIR/app" -c user.email=t@t.com -c user.name=T \
        commit -q --allow-empty -m init
    cat >"$PWT_DIR/projects/app/config" <<EOF
path=$TEST_TEMP_DIR/app
worktrees_dir=$TEST_TEMP_DIR/wts
base_port=$port
EOF
    cat >"$PWT_DIR/state/app/feat.meta" <<EOF
path=$TEST_TEMP_DIR/wts/feat
branch=feat
port=$port
mode=worktree
EOF
}

@test "pwt ports reports a system-held port as system, not listening" {
    _project_on_port 5000
    _stub_lsof 5000 4242 "$CONTROL_CENTER"
    _stub_ps 4242 "$CONTROL_CENTER"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" ports
    assert_success
    [[ "$output" == *"system"* ]] || {
        echo "expected a 'system' status, got: $output" >&2
        return 1
    }
    [[ "$output" != *"listening"* ]] || {
        echo "AirPlay on :5000 must not read as a running server: $output" >&2
        return 1
    }
}

@test "pwt ports --json does not claim a system-held port is listening" {
    _project_on_port 5000
    _stub_lsof 5000 4242 "$CONTROL_CENTER"
    _stub_ps 4242 "$CONTROL_CENTER"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" ports --json
    assert_success
    [[ "$output" == *'"listening":false'* ]] || {
        echo "expected listening:false, got: $output" >&2
        return 1
    }
    [[ "$output" == *'"system":true'* ]] || {
        echo "expected the reason to be machine readable, got: $output" >&2
        return 1
    }
}

@test "more than one system daemon on the machine still classifies" {
    # A single system pid hides the fact that awk -v rejects a literal
    # newline in the value it is handed, so this needs two
    _project_on_port 5000
    cat >"$STUB_BIN/lsof" <<'EOF'
#!/usr/bin/env bash
case "$*" in
*-iTCP*)
    echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
    echo "ControlCenter 4242 root 30u IPv4 0x1 0t0 TCP *:5000 (LISTEN)"
    echo "ControlCenter 4243 root 31u IPv4 0x2 0t0 TCP *:7000 (LISTEN)"
    echo "rapportd 4244 root 32u IPv4 0x3 0t0 TCP *:63321 (LISTEN)"
    ;;
*:5000*) echo 4242 ;;
*) exit 1 ;;
esac
EOF
    chmod +x "$STUB_BIN/lsof"
    cat >"$STUB_BIN/ps" <<EOF
#!/usr/bin/env bash
case "\$*" in
*pid=,command=*)
    printf '%5s %s\n' 4242 "$CONTROL_CENTER"
    printf '%5s %s\n' 4243 "$CONTROL_CENTER"
    printf '%5s %s\n' 4244 "/usr/libexec/rapportd"
    ;;
*4242*) echo "$CONTROL_CENTER" ;;
*) exec /bin/ps "\$@" ;;
esac
EOF
    chmod +x "$STUB_BIN/ps"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" ports --json
    assert_success
    [[ "$output" != *"awk"* ]] || {
        echo "the classifier leaked an awk error: $output" >&2
        return 1
    }
    [[ "$output" == *'"system":true'* ]] || {
        echo "expected system:true, got: $output" >&2
        return 1
    }
}

@test "a real server on the same port is still reported as listening" {
    _project_on_port 5000
    _stub_lsof 5000 4242 "/usr/local/bin/puma"
    _stub_ps 4242 "puma 6.4.0 (tcp://0.0.0.0:5000)"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" ports --json
    assert_success
    [[ "$output" == *'"listening":true'* ]] || {
        echo "expected listening:true, got: $output" >&2
        return 1
    }
}

# ============================================
# Readiness must not be satisfied by a daemon
# ============================================

@test "server wait refuses a port it can never own, instead of reporting ready" {
    _project_on_port 5000
    _stub_lsof 5000 4242 "$CONTROL_CENTER"
    _stub_ps 4242 "$CONTROL_CENTER"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" server wait feat --timeout 2
    [ "$status" -ne 0 ] || {
        echo "a daemon answering the probe must not count as ready: $output" >&2
        return 1
    }
    [[ "$output" == *"system daemon"* ]] || {
        echo "the reason has to be in the message, got: $output" >&2
        return 1
    }
    [[ "$output" == *"fix-port"* ]] || {
        echo "expected a way out, got: $output" >&2
        return 1
    }
}

# ============================================
# A daemon is never a blocker, and never a target
# ============================================

@test "remove is not blocked by a system daemon holding the port" {
    _project_on_port 5000
    _stub_lsof 5000 4242 "$CONTROL_CENTER"
    _stub_ps 4242 "$CONTROL_CENTER"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" --no-input remove feat -y
    [[ "$output" != *"Processes detected on port"* ]] || {
        echo "AirPlay must not block a removal: $output" >&2
        return 1
    }
}

@test "kill-port never offers a system daemon as something to kill" {
    _project_on_port 5000
    _stub_lsof 5000 4242 "$CONTROL_CENTER"
    _stub_ps 4242 "$CONTROL_CENTER"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" --no-input remove feat --kill-port -y
    [[ "$output" != *"Processes on port"* ]] || {
        echo "kill -9 on ControlCenter is never what remove meant: $output" >&2
        return 1
    }
    [[ "$output" != *"4242"* ]] || {
        echo "the daemon's pid must not appear as a kill target: $output" >&2
        return 1
    }
}

@test "info does not report a system daemon as the worktree's server" {
    _project_on_port 5000
    _stub_lsof 5000 4242 "$CONTROL_CENTER"
    _stub_ps 4242 "$CONTROL_CENTER"

    cd "$TEST_TEMP_DIR/app"
    PATH="$STUB_BIN:$PATH" run "$PWT_BIN" info feat
    [[ "$output" != *"running"* ]] || {
        echo "no server is running here: $output" >&2
        return 1
    }
}

# ============================================
# The main checkout's port comes from the project
# ============================================

@test "list -v checks the project's base port, not a hardcoded 5000" {
    _project_on_port 43977

    cd "$TEST_TEMP_DIR/app"
    run "$PWT_BIN" list -v
    assert_success
    [[ "$output" == *"43977"* ]] || {
        echo "main checkout must be checked on its own port: $output" >&2
        return 1
    }
    [[ "$output" != *"5000"* ]] || {
        echo "5000 is hardcoded; a project on another base port is misreported" >&2
        return 1
    }
}
