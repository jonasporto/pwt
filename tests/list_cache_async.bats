#!/usr/bin/env bats
# A stale list cache is served instantly and refreshed by a detached
# background run; only the first-ever list computes synchronously.

load test_helper

setup() {
    setup_test_env
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"
    mkdir -p "$PWT_DIR/projects/test-repo"
    cat >"$PWT_DIR/projects/test-repo/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
EOF
    cd "$TEST_REPO"
    echo "content" >file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    teardown_test_env
}

_cache_file() {
    ls "$PWT_DIR"/cache/*test-repo* 2>/dev/null | grep -v regen-stamp | head -1
}

@test "stale cache is served instantly and refreshed in background" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-ASYNC HEAD >/dev/null

    # Populate the cache, then make it stale AND poison it with a marker
    "$PWT_BIN" list >/dev/null
    local cache; cache=$(_cache_file)
    [ -n "$cache" ]
    echo "STALE-MARKER-ROW" >>"$cache"
    touch -t 202001010000 "$cache"

    # The stale content must be served (instant path), not recomputed
    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE-MARKER-ROW"* ]]

    # The detached regen must rewrite the cache shortly after. The regen
    # deletes the cache before recomputing, so wait for the REWRITTEN file
    # (real rows present, marker gone), not merely for the marker to vanish.
    local tries=0
    until grep -q "WT-ASYNC" "$cache" 2>/dev/null && ! grep -q "STALE-MARKER-ROW" "$cache" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -gt 150 ] && break
        sleep 0.2
    done
    ! grep -q "STALE-MARKER-ROW" "$cache"
    grep -q "WT-ASYNC" "$cache"
}

@test "PWT_LIST_ASYNC_REFRESH=0 keeps the blocking regeneration" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-SYNC HEAD >/dev/null
    "$PWT_BIN" list >/dev/null
    local cache; cache=$(_cache_file)
    echo "STALE-MARKER-ROW" >>"$cache"
    touch -t 202001010000 "$cache"

    PWT_LIST_ASYNC_REFRESH=0 run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" != *"STALE-MARKER-ROW"* ]]
    [[ "$output" == *"WT-SYNC"* ]]
}

@test "first-ever list still computes synchronously" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-FIRST HEAD >/dev/null
    rm -f "$PWT_DIR"/cache/* 2>/dev/null || true
    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-FIRST"* ]]
}

@test "porcelain is cached and --refresh regenerates it" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PORC HEAD >/dev/null

    run "$PWT_BIN" list --porcelain
    [ "$status" -eq 0 ]
    [[ "$output" == *'"generated_at"'* ]]
    [[ "$output" == *"WT-PORC"* ]]

    # Second call must come from cache (identical generated_at)
    local first_gen; first_gen=$(echo "$output" | grep generated_at)
    run "$PWT_BIN" list --porcelain
    [[ "$output" == *"$first_gen"* ]]

    # --refresh recomputes: newer generated_at (allow same-second by touch)
    sleep 1
    run "$PWT_BIN" list --porcelain --refresh
    [ "$status" -eq 0 ]
    [[ "$output" != *"$first_gen"* ]]
}

@test "metadata writes invalidate the porcelain cache too" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PINV HEAD >/dev/null
    "$PWT_BIN" list --porcelain >/dev/null
    "$PWT_BIN" meta set WT-PINV phase review >/dev/null

    run "$PWT_BIN" list --porcelain
    [ "$status" -eq 0 ]
    # Cache was cleared, so this is a fresh document listing the worktree
    [[ "$output" == *"WT-PINV"* ]]
}
