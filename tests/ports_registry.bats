#!/usr/bin/env bats
# Ports are a machine-wide resource: allocation must consider every
# project, and `pwt ports` is the registry view over all of them.

load test_helper

setup() {
    setup_test_env
    # Two projects that both want to start at the same base, which is the
    # normal case: every framework's default is the same number
    for p in alpha beta; do
        mkdir -p "$PWT_DIR/projects/$p" "$TEST_TEMP_DIR/$p-wts"
        git init -q -b main "$TEST_TEMP_DIR/$p"
        git -C "$TEST_TEMP_DIR/$p" -c user.email=t@t.com -c user.name=T \
            commit -q --allow-empty -m init
        cat >"$PWT_DIR/projects/$p/config" <<EOF
path=$TEST_TEMP_DIR/$p
worktrees_dir=$TEST_TEMP_DIR/$p-wts
base_port=8000
EOF
    done
}

teardown() {
    teardown_test_env
}

_port_of() {
    grep '^port=' "$PWT_DIR/state/$1/$2.meta" | cut -d= -f2
}

@test "two projects sharing a base port never get the same allocation" {
    cd "$TEST_TEMP_DIR/alpha"
    "$PWT_BIN" create WT-A main >/dev/null
    cd "$TEST_TEMP_DIR/beta"
    "$PWT_BIN" create WT-B main >/dev/null

    local a b
    a=$(_port_of alpha WT-A)
    b=$(_port_of beta WT-B)
    [ -n "$a" ] && [ -n "$b" ]
    [ "$a" != "$b" ]
}

@test "allocation also avoids another project's base port" {
    # beta's base is 8000; alpha's worktrees must never land on it
    cd "$TEST_TEMP_DIR/alpha"
    "$PWT_BIN" create WT-BASE main >/dev/null
    [ "$(_port_of alpha WT-BASE)" != "8000" ]
}

@test "pwt ports lists allocations from every project" {
    cd "$TEST_TEMP_DIR/alpha"
    "$PWT_BIN" create WT-ONE main >/dev/null
    cd "$TEST_TEMP_DIR/beta"
    "$PWT_BIN" create WT-TWO main >/dev/null

    run "$PWT_BIN" ports
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-ONE"* ]]
    [[ "$output" == *"WT-TWO"* ]]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

@test "pwt ports flags a port claimed twice" {
    cd "$TEST_TEMP_DIR/alpha"
    "$PWT_BIN" create WT-DUP1 main >/dev/null
    cd "$TEST_TEMP_DIR/beta"
    "$PWT_BIN" create WT-DUP2 main >/dev/null
    # Force the collision that pre-0.2.8 state can contain
    local p
    p=$(_port_of alpha WT-DUP1)
    "$PWT_BIN" --project beta meta set WT-DUP2 port "$p" >/dev/null

    run "$PWT_BIN" ports
    [ "$status" -eq 0 ]
    [[ "$output" == *"conflict"* ]]
    [[ "$output" == *"fix-port"* ]]
}

@test "pwt ports --json is machine readable" {
    cd "$TEST_TEMP_DIR/alpha"
    "$PWT_BIN" create WT-JSON main >/dev/null

    run "$PWT_BIN" ports --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"ports"'* ]]
    [[ "$output" == *'"conflict"'* ]]
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['ports'], 'empty'" "$output"
    fi
}

@test "pwt ports with no allocations says so" {
    rm -rf "$PWT_DIR/state"
    cd "$TEST_TEMP_DIR/alpha"
    run "$PWT_BIN" ports
    [ "$status" -eq 0 ]
    # Base ports still count as allocations; only a stateless dir is empty
    [[ "$output" == *"8000"* || "$output" == *"No ports allocated"* ]]
}
