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
    source_pwt_functions next_available_port meta_ports meta_ports_all meta_base_ports_all state_get _meta_read_key_var _state_unescape _state_unescape_var

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

@test "allocation reuses a hole past the first hundred ports" {
    source_pwt_functions next_available_port state_get _state_unescape _state_unescape_var
    BASE_PORT=6000
    WORKTREES_DIR="$TEST_TEMP_DIR/none"
    meta_ports_all() {
        local p=6001
        while [ "$p" -le 6150 ]; do
            [ "$p" -eq 6120 ] || printf '%s\t-\t-\n' "$p"
            p=$((p + 1))
        done
    }
    meta_base_ports_all() { :; }
    is_port_pair_free() { return 0; }
    run next_available_port
    [ "$output" = "6120" ]
}

@test "allocation never hands out another worktree's public router port" {
    source_pwt_functions next_available_port state_get _state_unescape _state_unescape_var
    BASE_PORT=6000
    WORKTREES_DIR="$TEST_TEMP_DIR/none"
    mkdir -p "$PWT_DIR"
    printf 'router.port_offset=2\n' >"$PWT_DIR/config"
    # 6001 taken; 6003 = 6001 + offset is its public port; 6002 + 2 would
    # land on... nothing taken, but 6002 - 2 = 6000 is BASE (public 6002)
    meta_ports_all() { printf '6001\t-\t-\n'; }
    meta_base_ports_all() { :; }
    is_port_pair_free() { return 0; }
    run next_available_port
    [ "$output" = "6004" ]
}
