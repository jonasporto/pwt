#!/usr/bin/env bats
# Tests for helper functions

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================
# has_lsof tests
# ============================================

@test "has_lsof returns true when lsof is installed" {
    # Source the function
    source_pwt_function has_lsof

    # Reset cache
    _lsof_available=""

    if command -v lsof >/dev/null 2>&1; then
        run has_lsof
        [ "$status" -eq 0 ]
    else
        skip "lsof not installed on this system"
    fi
}

@test "has_lsof caches result" {
    source_pwt_function has_lsof

    # Reset and set cache manually
    _lsof_available="yes"
    run has_lsof
    [ "$status" -eq 0 ]

    _lsof_available="no"
    run has_lsof
    [ "$status" -ne 0 ]
}

# ============================================
# is_port_free tests
# ============================================

@test "is_port_free returns 0 for unused port" {
    source_pwt_functions has_lsof is_port_free

    # Reset lsof cache
    _lsof_available=""

    # Use a high port that's unlikely to be in use
    run is_port_free 59999
    [ "$status" -eq 0 ]
}

@test "get_pids_on_port reports the listener, never a client of the port" {
    # A connection matches `lsof -i :port` from EITHER end, so an
    # unqualified query hands clients of the port to every kill path:
    # remove --kill-port -y would SIGKILL a browser that merely has a tab
    # open on the port, and the identical pattern in test teardowns killed
    # the CI runner's own agent when its ephemeral port landed in a test's
    # port window. The ss/fuser fallbacks were always listener-only.
    command -v lsof >/dev/null 2>&1 || skip "exercises the lsof branch"
    command -v python3 >/dev/null 2>&1 || skip "python3 is required for the listener"

    source_pwt_functions has_lsof get_pids_on_port
    _lsof_available=""

    local port
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')

    python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
    local server_pid=$!
    local i
    for i in $(seq 1 50); do
        (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break
        sleep 0.1
    done

    # A separate process holding an ESTABLISHED connection to the port,
    # exec'd so the connection lives in exactly one PID we can assert on.
    bash -c "exec 3<>/dev/tcp/127.0.0.1/$port; exec sleep 30" &
    local client_pid=$!
    sleep 0.5

    run get_pids_on_port "$port"
    kill "$client_pid" "$server_pid" 2>/dev/null || true

    [[ "$output" == *"$server_pid"* ]] || {
        echo "listener $server_pid missing from: $output" >&2
        return 1
    }
    [[ "$output" != *"$client_pid"* ]] || {
        echo "client $client_pid offered as a port owner: $output" >&2
        return 1
    }
}

@test "is_port_free returns 0 when lsof unavailable (best effort)" {
    source_pwt_functions has_lsof is_port_free

    # Force lsof unavailable
    _lsof_available="no"

    run is_port_free 80
    [ "$status" -eq 0 ] # Should assume free
}

# ============================================
# require_cmd tests
# ============================================

@test "require_cmd succeeds for installed command" {
    source_pwt_function require_cmd

    run require_cmd bash
    [ "$status" -eq 0 ]
}

@test "require_cmd fails for missing command" {
    # pwt_error too: without it the assertion below matches bash's own
    # "pwt_error: command not found" (which is localized) instead of pwt's
    # message, so the test passes for the wrong reason on English systems.
    source_pwt_functions pwt_error require_cmd

    run require_cmd nonexistent_command_xyz123
    [ "$status" -ne 0 ]
    [[ "$output" == *"Required command not found: nonexistent_command_xyz123"* ]]
}

@test "require_cmd returns 1 for missing optional command" {
    source_pwt_function require_cmd

    run require_cmd nonexistent_command_xyz123 true
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "require_cmd shows install hint for git" {
    source_pwt_function require_cmd

    # Temporarily rename git (can't actually do this, so we test output format)
    # Instead, check that the function has the hint code
    local pwt_content=$(cat "$PWT_BIN")
    [[ "$pwt_content" == *"xcode-select --install"* ]]
}

@test "require_cmd shows install hint for jq" {
    source_pwt_function require_cmd

    local pwt_content=$(cat "$PWT_BIN")
    [[ "$pwt_content" == *"brew install jq"* ]]
}

# ============================================
# confirm_action tests
# ============================================

# Helper to test confirm_action with piped input
_test_confirm() {
    local input="$1"
    source_pwt_function confirm_action
    echo "$input" | confirm_action "Test?"
}

@test "confirm_action returns 0 for 'y'" {
    run _test_confirm "y"
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 0 for 'yes'" {
    run _test_confirm "yes"
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 0 for 'Y'" {
    run _test_confirm "Y"
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 1 for 'n'" {
    run _test_confirm "n"
    [ "$status" -ne 0 ]
}

@test "confirm_action returns 1 for empty input" {
    run _test_confirm ""
    [ "$status" -ne 0 ]
}

@test "confirm_action returns 1 for random input" {
    run _test_confirm "maybe"
    [ "$status" -ne 0 ]
}

# ============================================
# pwtfile_replace_literal tests
# ============================================

@test "pwtfile_replace_literal replaces literal string" {
    source_pwt_function pwtfile_replace_literal

    echo "database: test_db" >"$TEST_TEMP_DIR/test.yml"
    pwtfile_replace_literal "$TEST_TEMP_DIR/test.yml" "test_db" "test_db_wt5001"

    run cat "$TEST_TEMP_DIR/test.yml"
    [ "$output" = "database: test_db_wt5001" ]
}

@test "pwtfile_replace_literal handles ERB syntax safely" {
    source_pwt_function pwtfile_replace_literal

    echo "database: test<%= ENV['X']%>" >"$TEST_TEMP_DIR/test.yml"
    pwtfile_replace_literal "$TEST_TEMP_DIR/test.yml" "test<%= ENV['X']%>" "test_wt<%= ENV['X']%>"

    run cat "$TEST_TEMP_DIR/test.yml"
    [ "$output" = "database: test_wt<%= ENV['X']%>" ]
}

@test "pwtfile_replace_literal handles special regex chars" {
    source_pwt_function pwtfile_replace_literal

    echo "url: http://localhost:3000/api" >"$TEST_TEMP_DIR/test.txt"
    pwtfile_replace_literal "$TEST_TEMP_DIR/test.txt" "localhost:3000" "localhost:5001"

    run cat "$TEST_TEMP_DIR/test.txt"
    [ "$output" = "url: http://localhost:5001/api" ]
}

@test "pwtfile_replace_literal does nothing for missing file" {
    source_pwt_function pwtfile_replace_literal

    run pwtfile_replace_literal "$TEST_TEMP_DIR/nonexistent.txt" "a" "b"
    [ "$status" -eq 0 ]
}

# ============================================
# pwtfile_replace_re tests
# ============================================

@test "pwtfile_replace_re replaces regex pattern" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    echo "PORT=3000" >"$TEST_TEMP_DIR/test.env"
    pwtfile_replace_re "$TEST_TEMP_DIR/test.env" "PORT=\d+" "PORT=5001"

    run cat "$TEST_TEMP_DIR/test.env"
    [ "$output" = "PORT=5001" ]
}

@test "pwtfile_replace_re handles multiple matches" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    printf "port: 3000\nother_port: 3000\n" >"$TEST_TEMP_DIR/test.yml"
    pwtfile_replace_re "$TEST_TEMP_DIR/test.yml" "3000" "5001"

    run cat "$TEST_TEMP_DIR/test.yml"
    [[ "$output" == *"port: 5001"* ]]
    [[ "$output" == *"other_port: 5001"* ]]
}

@test "pwtfile_replace_re does nothing for missing file" {
    source_pwt_function pwtfile_replace_re

    run pwtfile_replace_re "$TEST_TEMP_DIR/nonexistent.txt" "a" "b"
    [ "$status" -eq 0 ]
}

# A replacement containing '/' used to close the s/// early: perl aborted with
# "Unknown regexp modifier" and left the file untouched. Paths are THE common
# replacement when rewriting a .env, so this is the primary use, not an edge.
@test "pwtfile_replace_re writes a replacement containing slashes" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    echo "DATABASE_URL=sqlite3:db/dev.sqlite3" >"$TEST_TEMP_DIR/test.env"
    run pwtfile_replace_re "$TEST_TEMP_DIR/test.env" \
        "DATABASE_URL=.*" "DATABASE_URL=/var/data/app_wt5001.sqlite3"
    [ "$status" -eq 0 ]

    run cat "$TEST_TEMP_DIR/test.env"
    [ "$output" = "DATABASE_URL=/var/data/app_wt5001.sqlite3" ]
}

@test "pwtfile_replace_re keeps the replacement literal (no perl interpolation)" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    echo "DATABASE_URL=old" >"$TEST_TEMP_DIR/test.env"
    # '@host' would be an array and '$pw' a scalar if the replacement were
    # interpolated as perl source; both must survive verbatim.
    pwtfile_replace_re "$TEST_TEMP_DIR/test.env" \
        "DATABASE_URL=.*" 'DATABASE_URL=postgres://u:p@host/db$pw'

    run cat "$TEST_TEMP_DIR/test.env"
    [ "$output" = 'DATABASE_URL=postgres://u:p@host/db$pw' ]
}

@test "pwtfile_replace_re still treats the pattern as a regex" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    printf "port:   3000\n" >"$TEST_TEMP_DIR/test.yml"
    pwtfile_replace_re "$TEST_TEMP_DIR/test.yml" "port:\s*\d+" "port: 5001"

    run cat "$TEST_TEMP_DIR/test.yml"
    [ "$output" = "port: 5001" ]
}

# The recipe examples/Pwtfile.reference ships: a substring swap would leave
# PORT=50013000 behind, so the reference uses the line-anchored _re form.
@test "pwtfile_replace_re rewrites a key that already has a value" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    printf "PORT=3000\nOTHER=keep\n" >"$TEST_TEMP_DIR/test.env"
    pwtfile_replace_re "$TEST_TEMP_DIR/test.env" "PORT=.*" "PORT=5001"

    run cat "$TEST_TEMP_DIR/test.env"
    [[ "$output" == *"PORT=5001"* ]]
    [[ "$output" != *"3000"* ]]
    [[ "$output" == *"OTHER=keep"* ]]
}

# ============================================
# detect_submodules tests
# ============================================

@test "detect_submodules returns 0 when no .gitmodules" {
    source_pwt_functions confirm_action detect_submodules

    # TEST_REPO has no .gitmodules
    run detect_submodules "$TEST_REPO"
    [ "$status" -eq 0 ]
}

@test "detect_submodules warns when .gitmodules exists" {
    source_pwt_functions confirm_action detect_submodules

    # Create a .gitmodules file
    echo "[submodule \"vendor/lib\"]" >"$TEST_REPO/.gitmodules"

    run detect_submodules "$TEST_REPO"
    [[ "$output" == *"Submodules detected"* ]]
}
