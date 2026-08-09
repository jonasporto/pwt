#!/usr/bin/env bats
# Tests for state contract v2 helpers (key=value files, events log)

load test_helper

setup() {
    setup_test_env
    source_pwt_functions _state_escape _state_unescape state_get state_set \
        state_del state_list_prefix json_escape events_append \
        events_maybe_truncate state_version_read state_version_write
    PWT_STATE_VERSION=2
    STATE_FILE="$TEST_TEMP_DIR/sample.state"
}

teardown() {
    teardown_test_env
}

# --- state_set / state_get ---

@test "state_set creates file and state_get reads value back" {
    state_set "$STATE_FILE" "branch" "user/TICKET-123"
    run state_get "$STATE_FILE" "branch"
    assert_success
    [ "$output" = "user/TICKET-123" ]
}

@test "state_get on missing file returns empty with success" {
    run state_get "$TEST_TEMP_DIR/nope.state" "key"
    assert_success
    [ -z "$output" ]
}

@test "state_get on missing key returns empty" {
    state_set "$STATE_FILE" "a" "1"
    run state_get "$STATE_FILE" "b"
    assert_success
    [ -z "$output" ]
}

@test "state_set updates existing key in place preserving order" {
    state_set "$STATE_FILE" "a" "1"
    state_set "$STATE_FILE" "b" "2"
    state_set "$STATE_FILE" "c" "3"
    state_set "$STATE_FILE" "b" "22"
    run cat "$STATE_FILE"
    [ "${lines[0]}" = "a=1" ]
    [ "${lines[1]}" = "b=22" ]
    [ "${lines[2]}" = "c=3" ]
}

@test "state_set preserves unknown keys" {
    printf 'phase=review\nnext=address comments\n' > "$STATE_FILE"
    state_set "$STATE_FILE" "port" "5024"
    run state_get "$STATE_FILE" "phase"
    [ "$output" = "review" ]
    run state_get "$STATE_FILE" "next"
    [ "$output" = "address comments" ]
    run state_get "$STATE_FILE" "port"
    [ "$output" = "5024" ]
}

@test "state_set creates parent directories" {
    local nested="$TEST_TEMP_DIR/deep/dir/file.meta"
    state_set "$nested" "k" "v"
    [ -f "$nested" ]
}

@test "keys are matched exactly, not by prefix" {
    state_set "$STATE_FILE" "base" "main"
    state_set "$STATE_FILE" "base_commit" "abc1234"
    run state_get "$STATE_FILE" "base"
    [ "$output" = "main" ]
    run state_get "$STATE_FILE" "base_commit"
    [ "$output" = "abc1234" ]
}

@test "value may contain equals signs (split on first = only)" {
    state_set "$STATE_FILE" "cmd" "FOO=bar make run"
    run state_get "$STATE_FILE" "cmd"
    [ "$output" = "FOO=bar make run" ]
}

@test "newline in value round-trips via escaping" {
    state_set "$STATE_FILE" "desc" $'line1\nline2'
    # File stays one line per key
    run wc -l < "$STATE_FILE"
    [ "$(echo $output)" = "1" ]
    local got
    got=$(state_get "$STATE_FILE" "desc")
    [ "$got" = $'line1\nline2' ]
}

@test "backslash in value round-trips via escaping" {
    state_set "$STATE_FILE" "path" 'C:\temp\new'
    local got
    got=$(state_get "$STATE_FILE" "path")
    [ "$got" = 'C:\temp\new' ]
}

@test "escaped file content uses backslash-n, not raw newline" {
    state_set "$STATE_FILE" "desc" $'a\nb'
    run cat "$STATE_FILE"
    [ "$output" = 'desc=a\nb' ]
}

@test "state_del removes only the named key" {
    state_set "$STATE_FILE" "a" "1"
    state_set "$STATE_FILE" "b" "2"
    state_del "$STATE_FILE" "a"
    run state_get "$STATE_FILE" "a"
    [ -z "$output" ]
    run state_get "$STATE_FILE" "b"
    [ "$output" = "2" ]
}

@test "state_del on missing key or file is a no-op" {
    run state_del "$TEST_TEMP_DIR/nope.state" "a"
    assert_success
    state_set "$STATE_FILE" "b" "2"
    run state_del "$STATE_FILE" "a"
    assert_success
    run state_get "$STATE_FILE" "b"
    [ "$output" = "2" ]
}

@test "dotted keys work (nested concepts flatten with dots)" {
    state_set "$STATE_FILE" "editor.default" "vim"
    state_set "$STATE_FILE" "ai.tools.claude" "claude --resume"
    run state_get "$STATE_FILE" "editor.default"
    [ "$output" = "vim" ]
    run state_get "$STATE_FILE" "ai.tools.claude"
    [ "$output" = "claude --resume" ]
}

@test "state_list_prefix lists subkeys with values" {
    state_set "$STATE_FILE" "ai.tools.claude" "claude"
    state_set "$STATE_FILE" "ai.tools.aider" "aider --model foo"
    state_set "$STATE_FILE" "ai.default" "claude"
    run state_list_prefix "$STATE_FILE" "ai.tools"
    assert_success
    [ "${lines[0]}" = "$(printf 'claude\tclaude')" ]
    [ "${lines[1]}" = "$(printf 'aider\taider --model foo')" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "empty value round-trips" {
    state_set "$STATE_FILE" "desc" ""
    run grep -c '^desc=$' "$STATE_FILE"
    [ "$output" = "1" ]
    run state_get "$STATE_FILE" "desc"
    [ -z "$output" ]
}

# --- json_escape ---

@test "json_escape escapes quotes and backslashes" {
    run json_escape 'say "hi" c:\path'
    [ "$output" = 'say \"hi\" c:\\path' ]
}

@test "json_escape escapes newlines and tabs" {
    local got
    got=$(json_escape $'a\nb\tc')
    [ "$got" = 'a\nb\tc' ]
}

@test "json_escape passes plain strings through" {
    run json_escape 'plain-text_123'
    [ "$output" = 'plain-text_123' ]
}

# --- events log ---

@test "events_append writes TSV line with timestamp" {
    events_append "myproj" "TICKET-1" "create" "branch=user/TICKET-1"
    [ -f "$PWT_DIR/events.log" ]
    run tail -1 "$PWT_DIR/events.log"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z ]]
    local rest="${output#*	}"
    [ "$rest" = "$(printf 'myproj\tTICKET-1\tcreate\tbranch=user/TICKET-1')" ]
}

@test "events_append appends, never truncates" {
    events_append "p" "w" "create" ""
    events_append "p" "w" "remove" ""
    run wc -l < "$PWT_DIR/events.log"
    [ "$(echo $output)" = "2" ]
}

@test "events_maybe_truncate keeps small logs untouched" {
    events_append "p" "w" "create" ""
    events_maybe_truncate
    run wc -l < "$PWT_DIR/events.log"
    [ "$(echo $output)" = "1" ]
}

@test "events_maybe_truncate trims oversized log to last 1000 lines" {
    local i=0
    { while [ $i -lt 2500 ]; do echo "ts	p	w	k	$i"; i=$((i+1)); done; } > "$PWT_DIR/events.log"
    events_maybe_truncate
    run wc -l < "$PWT_DIR/events.log"
    [ "$(echo $output)" = "1000" ]
    run tail -1 "$PWT_DIR/events.log"
    [ "$output" = "$(printf 'ts\tp\tw\tk\t2499')" ]
}

# --- state version ---

@test "state_version_write then read returns 2" {
    state_version_write
    run state_version_read
    [ "$output" = "2" ]
    run cat "$PWT_DIR/state-version"
    [ "$output" = "2" ]
}

@test "state_version_read on fresh dir is empty and succeeds" {
    rm -f "$PWT_DIR/state-version"
    run state_version_read
    assert_success
    [ -z "$output" ]
}

# --- migration (v1 JSON -> v2 key=value) ---

seed_legacy_state() {
    rm -f "$PWT_DIR/state-version"
    mkdir -p "$PWT_DIR/projects/legacy-proj" "$PWT_DIR/jobs" "$PWT_DIR/trash"
    echo '{"legacy-proj":{"WT-1":{"path":"/tmp/x/WT-1","branch":"feat/WT-1","port":5001,"description":"legacy wt","phase":"review"}}}' > "$PWT_DIR/meta.json"
    echo '{"path":"/tmp/x","worktrees_dir":"/tmp/x-worktrees","alias":"lp","aliases":["l2","l3"]}' > "$PWT_DIR/projects/legacy-proj/config.json"
    echo '{"ai":{"default":"claude","tools":{"claude":"claude --resume"}}}' > "$PWT_DIR/config.json"
    echo '{"id":"j1","pid":12345,"pgid":12345,"command":"server","worktree":"WT-1","project":"legacy-proj","log":"/tmp/j1.log","started_at":"2026-01-01T00:00:00Z","status":"stopped"}' > "$PWT_DIR/jobs/j1.json"
    echo '{"worktree":"WT-9","branch":"feat/WT-9","base":"master","port":"5009","description":"","project":"legacy-proj","timestamp":"20260101_000000","date":"2026-01-01 00:00:00"}' > "$PWT_DIR/trash/WT-9_20260101_000000.json"
}

@test "migration: legacy JSON state converts on first command" {
    seed_legacy_state
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]

    # version declared
    [ "$(cat "$PWT_DIR/state-version")" = "2" ]

    # meta.json -> per-worktree meta file
    [ -f "$PWT_DIR/state/legacy-proj/WT-1.meta" ]
    grep -q '^branch=feat/WT-1$' "$PWT_DIR/state/legacy-proj/WT-1.meta"
    grep -q '^port=5001$' "$PWT_DIR/state/legacy-proj/WT-1.meta"
    # user-defined keys survive
    grep -q '^phase=review$' "$PWT_DIR/state/legacy-proj/WT-1.meta"

    # project config -> key=value with aliases CSV
    [ -f "$PWT_DIR/projects/legacy-proj/config" ]
    grep -q '^path=/tmp/x$' "$PWT_DIR/projects/legacy-proj/config"
    grep -q '^aliases=l2,l3$' "$PWT_DIR/projects/legacy-proj/config"

    # global config -> dotted keys
    grep -q '^ai\.default=claude$' "$PWT_DIR/config"
    grep -q '^ai\.tools\.claude=claude --resume$' "$PWT_DIR/config"

    # jobs and trash records
    [ -f "$PWT_DIR/jobs/j1.job" ]
    grep -q '^pid=12345$' "$PWT_DIR/jobs/j1.job"
    [ -f "$PWT_DIR/trash/WT-9_20260101_000000.trash" ]
    grep -q '^worktree=WT-9$' "$PWT_DIR/trash/WT-9_20260101_000000.trash"
}

@test "migration: legacy sources are kept as .v1.bak" {
    seed_legacy_state
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
    [ -f "$PWT_DIR/meta.json.v1.bak" ]
    [ -f "$PWT_DIR/config.json.v1.bak" ]
    [ -f "$PWT_DIR/projects/legacy-proj/config.json.v1.bak" ]
    [ -f "$PWT_DIR/jobs/j1.json.v1.bak" ]
    [ ! -f "$PWT_DIR/meta.json" ]
    [ ! -f "$PWT_DIR/config.json" ]
}

@test "migration: runs only once (state-version short-circuits)" {
    seed_legacy_state
    "$PWT_BIN" project list >/dev/null 2>&1
    # Re-seed a legacy file; with state-version present it must NOT be touched
    echo '{}' > "$PWT_DIR/meta.json"
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
    [ -f "$PWT_DIR/meta.json" ]
    [[ "$output" != *"Migrating"* ]]
}

@test "migration: migrated project resolves by alias" {
    seed_legacy_state
    # Dispatch-level alias resolution: 'pwt lp <cmd>' resolves to legacy-proj
    run "$PWT_BIN" lp alias
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy-proj"* ]]
}

@test "fresh install writes state-version 2 without migration" {
    rm -f "$PWT_DIR/state-version"
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
    [[ "$output" != *"Migrating"* ]]
    [ "$(cat "$PWT_DIR/state-version")" = "2" ]
}

@test "pwt doctor reports leftover .v1.bak files" {
    seed_legacy_state
    "$PWT_BIN" project list >/dev/null 2>&1
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"v1.bak"* ]]
    [[ "$output" == *"Legacy state backups"* ]]
}

@test "pwt doctor treats jq as optional" {
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"jq"* ]]
    [[ "$output" == *"optional"* ]]
    [[ "$output" != *"jq: not installed (required)"* ]]
}

# --- pwt state --json ---

@test "pwt state --json emits versioned snapshot of projects, worktrees, jobs" {
    mkdir -p "$PWT_DIR/projects/snap-proj" "$PWT_DIR/state/snap-proj" "$PWT_DIR/jobs"
    printf 'path=/tmp/snap\nworktrees_dir=/tmp/snap-worktrees\n' > "$PWT_DIR/projects/snap-proj/config"
    printf 'branch=feat/S-1\nport=5100\nphase=doing\n' > "$PWT_DIR/state/snap-proj/S-1.meta"
    printf 'id=job9\npid=999\ncommand=server\nworktree=S-1\nproject=snap-proj\nstatus=stopped\n' > "$PWT_DIR/jobs/job9.job"

    run "$PWT_BIN" state --json
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null   # valid JSON
    [ "$(echo "$output" | jq -r '.schema_version')" = "2" ]
    [ "$(echo "$output" | jq -r '.projects["snap-proj"].path')" = "/tmp/snap" ]
    [ "$(echo "$output" | jq -r '.worktrees["snap-proj"]["S-1"].port')" = "5100" ]
    [ "$(echo "$output" | jq -r '.worktrees["snap-proj"]["S-1"].phase')" = "doing" ]
    [ "$(echo "$output" | jq -r '.jobs[0].id')" = "job9" ]
}

@test "pwt state --json with empty state emits empty collections" {
    run "$PWT_BIN" state --json
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null
    [ "$(echo "$output" | jq -r '.projects | length')" = "0" ]
    [ "$(echo "$output" | jq -r '.jobs | length')" = "0" ]
}

@test "pwt state --help shows usage" {
    run "$PWT_BIN" state --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pwt state [--json]"* ]]
}

@test "pwt help mentions state --json" {
    run "$PWT_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"state --json"* ]]
}

# --- events emitted by lifecycle commands ---

@test "create and remove emit events to events.log" {
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES" "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config" << EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
EOF
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-EVENTS HEAD
    grep -q "	test-project	WT-EVENTS	create	" "$PWT_DIR/events.log"

    "$PWT_BIN" remove WT-EVENTS -y
    grep -q "	test-project	WT-EVENTS	remove	" "$PWT_DIR/events.log"
}

@test "meta set emits meta_change event" {
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES" "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config" << EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
EOF
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-MEVENT HEAD
    "$PWT_BIN" meta set WT-MEVENT phase review
    grep -q "	test-project	WT-MEVENT	meta_change	phase=review" "$PWT_DIR/events.log"
}

# Regression: a real install accumulated a worktree written at PROJECT level
# (fields directly under the top-level key). jq aborts the whole stream when it
# tries to iterate that string, so every entry ordered AFTER it was silently
# dropped - and meta.json was renamed to .v1.bak as if all had migrated.
@test "migration: a malformed legacy entry does not truncate the rest" {
    rm -f "$PWT_DIR/state-version"
    mkdir -p "$PWT_DIR/projects/proj-a"
    cat > "$PWT_DIR/meta.json" << 'JSON'
{
  "proj-a": {"WT-A": {"path": "/tmp/a", "branch": "feat/a", "port": 5001}},
  "STRAY-123": {"path": "/tmp/stray", "branch": "feat/stray", "port": 5099},
  "proj-b": {"WT-B": {"path": "/tmp/b", "branch": "feat/b", "port": 5002}},
  "proj-c": {"WT-C": {"path": "/tmp/c", "branch": "feat/c", "port": 5003}}
}
JSON

    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]

    # Entries before AND after the malformed one must survive
    [ -f "$PWT_DIR/state/proj-a/WT-A.meta" ]
    [ -f "$PWT_DIR/state/proj-b/WT-B.meta" ]
    [ -f "$PWT_DIR/state/proj-c/WT-C.meta" ]
    grep -q '^port=5003$' "$PWT_DIR/state/proj-c/WT-C.meta"

    # The malformed entry is reported, not silently swallowed
    [[ "$output" == *"skipped malformed legacy entries"* ]] || \
        grep -q "STRAY-123" <<< "$output"

    # ...and is still recoverable from the backup
    [ -f "$PWT_DIR/meta.json.v1.bak" ]
    grep -q 'STRAY-123' "$PWT_DIR/meta.json.v1.bak"
}

@test "migration: unreadable meta.json aborts without touching state" {
    rm -f "$PWT_DIR/state-version"
    echo '{ this is not json' > "$PWT_DIR/meta.json"

    run "$PWT_BIN" project list
    [ "$status" -ne 0 ]

    # Original left in place: nothing renamed, no partial state written
    [ -f "$PWT_DIR/meta.json" ]
    [ ! -f "$PWT_DIR/meta.json.v1.bak" ]
    [ ! -f "$PWT_DIR/state-version" ]
}

@test "jobs list --porcelain emits valid JSON for consumers" {
    mkdir -p "$PWT_DIR/jobs"
    cat > "$PWT_DIR/jobs/consumer-test.job" << 'JOB'
id=consumer-test
pid=999999
command=server
worktree=WT-1
project=test-project
log=/tmp/consumer-test.log
started_at=2026-01-01T00:00:00Z
status=stopped
JOB

    run "$PWT_BIN" jobs list --porcelain
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *"\"id\":\"consumer-test\""* ]]
    [[ "$output" == *"\"command\":\"server\""* ]]
    [[ "$output" == *"\"worktree\":\"WT-1\""* ]]
}

# --- pwt state migrate (the deliberate, inspectable path) ---

@test "state migrate --check is read-only and reports counts" {
    seed_legacy_state

    run "$PWT_BIN" state migrate --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 → 2"* ]]
    [[ "$output" == *"meta.json"* ]]

    # Nothing may have been converted by the dry run itself
    [ ! -f "$PWT_DIR/state-version" ]
    [ -f "$PWT_DIR/meta.json" ]
    [ ! -f "$PWT_DIR/meta.json.v1.bak" ]
}

@test "state migrate --check --porcelain emits JSON with skip names" {
    rm -f "$PWT_DIR/state-version"
    mkdir -p "$PWT_DIR/projects/proj-a"
    cat > "$PWT_DIR/meta.json" << 'JSON'
{
  "proj-a": {"WT-A": {"path": "/tmp/a", "port": 5001}},
  "STRAY-9": {"path": "/tmp/stray", "port": 5099}
}
JSON

    run "$PWT_BIN" state migrate --check --porcelain
    [ "$status" -eq 0 ]
    [[ "$output" == *'"from": 1'* ]]
    [[ "$output" == *'"to": 2'* ]]
    [[ "$output" == *'"converts":1'* ]]
    [[ "$output" == *'STRAY-9/path'* ]]
}

@test "state migrate --status reports pending then none" {
    seed_legacy_state

    run "$PWT_BIN" state migrate --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"001-v1-to-v2"* ]]

    run "$PWT_BIN" state migrate
    [ "$status" -eq 0 ]

    run "$PWT_BIN" state migrate --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"up to date"* ]]
}

@test "state migrate --verify confirms converted counts" {
    seed_legacy_state
    run "$PWT_BIN" state migrate
    [ "$status" -eq 0 ]

    run "$PWT_BIN" state migrate --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"state-version: 2"* ]]
}

@test "pwt migrate is accepted as an alias" {
    seed_legacy_state

    run "$PWT_BIN" migrate --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"001-v1-to-v2"* ]]
}

# Regression: JSON type followed the value's shape, so a branch that happens
# to be all digits serialized as a number and the same field changed type
# between worktrees. Type must follow the KEY.
@test "state --json keeps non-numeric keys as strings even when all-digit" {
    mkdir -p "$PWT_DIR/state/test-project"
    cat > "$PWT_DIR/state/test-project/WT-N.meta" << 'META'
branch=123
description=456
port=5001
META

    run "$PWT_BIN" state --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"branch": "123"'* ]] || [[ "$output" == *'"branch":"123"'* ]]
    [[ "$output" == *'"description": "456"'* ]] || [[ "$output" == *'"description":"456"'* ]]
    [[ "$output" == *'"port": 5001'* ]] || [[ "$output" == *'"port":5001'* ]]
}

# Regression: `pwt state migrate` called migrate_state_v1 unconditionally, so
# a brand-new install claimed to have found legacy JSON and demanded jq.
@test "state migrate on an empty state dir succeeds without legacy claims" {
    local empty_dir="$TEST_TEMP_DIR/empty-pwt"
    mkdir -p "$empty_dir"

    run env PWT_DIR="$empty_dir" "$PWT_BIN" state migrate
    [ "$status" -eq 0 ]
    [[ "$output" != *"legacy pwt state"* ]]
    [[ "$output" != *"jq is not installed"* ]]
}
