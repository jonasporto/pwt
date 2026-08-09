#!/usr/bin/env bats
# Tests for port allocation edge cases

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "next_available_port skips busy fallback port" {
    source_pwt_functions next_available_port meta_ports _meta_read_key_var _state_unescape

    # Override port availability to force fallback skip
    is_port_pair_free() {
        [ "$1" -eq 5002 ] && return 1
        return 0
    }

    CURRENT_PROJECT="test-project"
    WORKTREES_DIR="$TEST_TEMP_DIR/worktrees"
    BASE_PORT=5000
    mkdir -p "$WORKTREES_DIR"

    mkdir -p "$PWT_DIR/state/test-project"
    cat >"$PWT_DIR/state/test-project/wt1.meta" <<EOF_META
port=5001
EOF_META

    export PWT_PORT_MAX_ATTEMPTS=1
    export PWT_PORT_FALLBACK_ATTEMPTS=5

    run next_available_port
    [ "$status" -eq 0 ]
    [ "$output" -eq 5003 ]
}
