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
    ls "$PWT_DIR"/cache/*test-repo* 2>/dev/null |
        grep -v -e regen-stamp -e porcelain -e fetch-stamp | head -1
}

_porcelain_cache_file() {
    ls "$PWT_DIR"/cache/*.porcelain 2>/dev/null | head -1
}

@test "stale cache is served instantly and refreshed in background" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-ASYNC HEAD >/dev/null

    # Populate the cache, then make it stale AND poison it with a marker
    "$PWT_BIN" list >/dev/null
    local cache
    cache=$(_cache_file)
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
    local cache
    cache=$(_cache_file)
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
    local first_gen
    first_gen=$(echo "$output" | grep generated_at)
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

@test "stale serve prints an age note" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-NOTE HEAD >/dev/null
    "$PWT_BIN" list >/dev/null
    local cache
    cache=$(_cache_file)
    touch -t 202001010000 "$cache"

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"refreshing in background"* ]]
}

@test "a fresh regen stamp debounces a second background regen" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DEB HEAD >/dev/null
    "$PWT_BIN" list >/dev/null
    local cache
    cache=$(_cache_file)
    echo "STALE-MARKER-ROW" >>"$cache"
    touch -t 202001010000 "$cache"
    # Pretend a regen just started: fresh stamp
    touch "${cache}.regen-stamp"

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE-MARKER-ROW"* ]]
    sleep 2
    # Debounced: no regen ran, the poisoned cache is untouched
    grep -q "STALE-MARKER-ROW" "$cache"
}

@test "a dead regen (stamp older than the deadline) is retried" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-RETRY HEAD >/dev/null
    "$PWT_BIN" list >/dev/null
    local cache
    cache=$(_cache_file)
    echo "STALE-MARKER-ROW" >>"$cache"
    touch -t 202001010000 "$cache" "${cache}.regen-stamp"

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    local tries=0
    until grep -q "WT-RETRY" "$cache" 2>/dev/null && ! grep -q "STALE-MARKER-ROW" "$cache" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -gt 150 ] && break
        sleep 0.2
    done
    ! grep -q "STALE-MARKER-ROW" "$cache"
}

@test "readers never observe an empty or truncated cache during regen" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-ATOMIC HEAD >/dev/null
    "$PWT_BIN" list >/dev/null
    local cache
    cache=$(_cache_file)
    echo "STALE-MARKER-ROW" >>"$cache"
    touch -t 202001010000 "$cache"

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    # Poll the cache file while the detached regen replaces it: every
    # observation must be a complete document (old with marker, or new
    # with the real row). An empty/partial read means the write was not
    # atomic.
    local tries=0 content saw_empty=false
    while :; do
        content=$(cat "$cache" 2>/dev/null || true)
        if [ -z "$content" ]; then
            saw_empty=true
            break
        fi
        case "$content" in
        *STALE-MARKER-ROW*) ;;
        *WT-ATOMIC*) break ;;
        *)
            saw_empty=true
            break
            ;;
        esac
        tries=$((tries + 1))
        [ "$tries" -gt 300 ] && break
        sleep 0.1
    done
    [ "$saw_empty" = false ]
    grep -q "WT-ATOMIC" "$cache"
}

@test "stale porcelain is served verbatim and replaced by valid fresher JSON" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PSTALE HEAD >/dev/null
    "$PWT_BIN" list --porcelain >/dev/null
    local pcache
    pcache=$(_porcelain_cache_file)
    [ -f "$pcache" ]
    local old_gen
    old_gen=$(grep generated_at "$pcache")
    touch -t 202001010000 "$pcache"

    # Stale serve: byte-identical to the cached document
    run "$PWT_BIN" list --porcelain
    [ "$status" -eq 0 ]
    [[ "$output" == *"$old_gen"* ]]

    # The detached regen must land a NEW, parseable document
    local tries=0
    while grep -q "$old_gen" "$pcache" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -gt 150 ] && break
        sleep 0.2
    done
    ! grep -q "$old_gen" "$pcache"
    python3 -c "import json,sys; json.load(open('$pcache'))"
}

@test "quick mode serves stale cache without spawning a regen" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-QUICK HEAD >/dev/null
    "$PWT_BIN" list >/dev/null
    local cache
    cache=$(_cache_file)
    echo "STALE-MARKER-ROW" >>"$cache"
    touch -t 202001010000 "$cache"
    rm -f "${cache}.regen-stamp"

    run "$PWT_BIN" list --quick
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE-MARKER-ROW"* ]]
    [ ! -f "${cache}.regen-stamp" ]
    sleep 1
    grep -q "STALE-MARKER-ROW" "$cache"
}

@test "a metadata write invalidates the table cache so no stale data is served" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-TINV HEAD >/dev/null
    "$PWT_BIN" list >/dev/null
    "$PWT_BIN" meta set WT-TINV phase review >/dev/null

    # Cache was cleared: this list recomputes synchronously (no stale note)
    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" != *"refreshing in background"* ]]
    [[ "$output" == *"WT-TINV"* ]]
}

_tree_cache_file() {
    ls "$PWT_DIR"/cache/*.tree 2>/dev/null | head -1
}

@test "tree default variant is cached and stale-served with background regen" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-TREE HEAD >/dev/null
    "$PWT_BIN" tree >/dev/null
    local tcache
    tcache=$(_tree_cache_file)
    [ -n "$tcache" ]
    echo "STALE-TREE-MARKER" >>"$tcache"
    touch -t 202001010000 "$tcache"

    run "$PWT_BIN" tree
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE-TREE-MARKER"* ]]
    [[ "$output" == *"refreshing in background"* ]]

    local tries=0
    until grep -q "WT-TREE" "$tcache" 2>/dev/null && ! grep -q "STALE-TREE-MARKER" "$tcache" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -gt 150 ] && break
        sleep 0.2
    done
    ! grep -q "STALE-TREE-MARKER" "$tcache"
    grep -q "WT-TREE" "$tcache"
}

@test "tree flagged variants bypass the cache" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-TREEFLAG HEAD >/dev/null
    "$PWT_BIN" tree >/dev/null
    local tcache
    tcache=$(_tree_cache_file)
    echo "STALE-TREE-MARKER" >>"$tcache"

    # A flagged tree must not show cached content
    run "$PWT_BIN" tree --short
    [ "$status" -eq 0 ]
    [[ "$output" != *"STALE-TREE-MARKER"* ]]
}

@test "tree --refresh recomputes synchronously" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-TREEREF HEAD >/dev/null
    "$PWT_BIN" tree >/dev/null
    local tcache
    tcache=$(_tree_cache_file)
    echo "STALE-TREE-MARKER" >>"$tcache"
    touch -t 202001010000 "$tcache"

    run "$PWT_BIN" tree --refresh
    [ "$status" -eq 0 ]
    [[ "$output" != *"STALE-TREE-MARKER"* ]]
    [[ "$output" == *"WT-TREEREF"* ]]
    grep -q "WT-TREEREF" "$tcache"
}

@test "metadata writes invalidate the tree cache" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-TREEINV HEAD >/dev/null
    "$PWT_BIN" tree >/dev/null
    local tcache
    tcache=$(_tree_cache_file)
    [ -n "$tcache" ]
    "$PWT_BIN" meta set WT-TREEINV phase review >/dev/null
    [ ! -f "$tcache" ]
}
