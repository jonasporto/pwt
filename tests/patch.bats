#!/usr/bin/env bats
# Tests for `pwt patch apply` and `pwt patch export`: commits made somewhere
# else land on a worktree as commits, in one command, or not at all.
#
# Every assertion uses `[ ]` or `case`: under macOS bash 3.2 a failing `[[ ]]`
# in the middle of a test does not fail the test. Redirects use `>|` because
# the CI nounset harness sets noclobber.

load test_helper

setup() {
    setup_test_env

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"
    export TEST_BASE_PORT=$((47000 + RANDOM % 400))
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >|"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
EOF

    cd "$TEST_REPO"
    printf 'content\n' >|file.txt
    git add file.txt
    git commit -q -m "Add file"
    export DEFAULT_BRANCH
    DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    export BASE_SHA
    BASE_SHA=$(git rev-parse HEAD)
    export MBOX="$TEST_TEMP_DIR/change.patch"
    export TRASH_DIR="$PWT_DIR/trash"
}

teardown() {
    if [ -n "${SLEEP_PID:-}" ]; then
        kill "$SLEEP_PID" 2>/dev/null || true
    fi
    teardown_test_env
}

# `case` instead of `[[ == * ]]`: see the file header
assert_has() {
    case "$output" in
        *"$1"*) return 0 ;;
    esac
    echo "expected output to contain: $1" >&2
    echo "$output" >&2
    return 1
}

assert_lacks() {
    case "$output" in
        *"$1"*)
            echo "expected output NOT to contain: $1" >&2
            echo "$output" >&2
            return 1
            ;;
    esac
    return 0
}

_commit_as_change_author() {
    git -c user.name="Change Author" -c user.email="change@example.com" commit -q "$@"
}

# Two commits on a `change` branch of the test repo, exported as a mailbox.
# Leaves the repo back on the default branch, at the base.
_make_change() {
    cd "$TEST_REPO"
    git checkout -q -b change
    printf 'content\nd\n' >|file.txt
    _commit_as_change_author -am "add d"
    echo "new" >|g.txt
    git add g.txt
    _commit_as_change_author -m "add g"
    git format-patch --stdout "$DEFAULT_BRANCH"..change >|"$MBOX"
    git checkout -q "$DEFAULT_BRANCH"
}

# A third change (a new file plus a line in g.txt); the mailbox now
# holds three
_extend_change() {
    cd "$TEST_REPO"
    git checkout -q change
    echo "third" >|h.txt
    echo "more" >>g.txt
    git add h.txt g.txt
    _commit_as_change_author -m "add h"
    git format-patch --stdout "$DEFAULT_BRANCH"..change >|"$MBOX"
    git checkout -q "$DEFAULT_BRANCH"
}

_create_wt() {
    cd "$TEST_REPO"
    "$PWT_BIN" create "$1" "$DEFAULT_BRANCH" --no-use >/dev/null
}

_wt_head() {
    git -C "$TEST_WORKTREES/$1" rev-parse HEAD
}

_wt_commit_count() {
    git -C "$TEST_WORKTREES/$1" rev-list --count HEAD
}

# ============================================
# apply: the happy path
# ============================================

@test "patch apply lands the mailbox commits on the worktree, authors kept" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    assert_has "add d"
    assert_has "add g"
    assert_has "reset --keep $BASE_SHA"

    [ "$(_wt_commit_count WT)" -eq 4 ]
    [ "$(git -C "$TEST_WORKTREES/WT" log -1 --format=%an)" = "Change Author" ]
    [ -f "$TEST_WORKTREES/WT/g.txt" ]
    [ "$(git -C "$TEST_WORKTREES/WT" status --porcelain | wc -l | tr -d ' ')" -eq 0 ]
}

@test "patch apply skips commits the branch already has" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"
    "$PWT_BIN" patch apply WT "$MBOX" >/dev/null
    local before
    before=$(_wt_head WT)

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    assert_has "skipped 2"
    [ "$(_wt_head WT)" = "$before" ]
}

@test "patch apply of a second round takes only the new commits" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"
    "$PWT_BIN" patch apply WT "$MBOX" >/dev/null
    _extend_change
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    assert_has "add h"
    assert_has "skipped 2"
    [ "$(_wt_commit_count WT)" -eq 5 ]
}

@test "patch apply reads the mailbox from stdin with -" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT - <"$MBOX"
    [ "$status" -eq 0 ]
    [ "$(_wt_commit_count WT)" -eq 4 ]
}

@test "patch apply works in the worktree-first form" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"

    run "$PWT_BIN" WT patch apply "$MBOX"
    [ "$status" -eq 0 ]
    [ "$(_wt_commit_count WT)" -eq 4 ]
}

@test "patch apply without a worktree uses the one the shell stands in" {
    _create_wt WT
    _make_change
    cd "$TEST_WORKTREES/WT"

    run "$PWT_BIN" patch apply "$MBOX"
    [ "$status" -eq 0 ]
    [ "$(_wt_commit_count WT)" -eq 4 ]
}

@test "patch apply with an empty input is a usage error" {
    _create_wt WT
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT - </dev/null
    [ "$status" -eq 2 ]
    [ "$(_wt_commit_count WT)" -eq 2 ]
}

@test "patch apply with a missing file exits 3" {
    _create_wt WT
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$TEST_TEMP_DIR/nope.patch"
    [ "$status" -eq 3 ]
}

@test "patch apply with an unknown worktree exits 3" {
    _make_change
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply NOPE "$MBOX"
    [ "$status" -eq 3 ]
}

# ============================================
# apply: refusals (exit 4, nothing changed, no backup written)
# ============================================

@test "patch apply refuses when a touched file has local edits" {
    _create_wt WT
    _make_change
    echo "local edit" >>"$TEST_WORKTREES/WT/file.txt"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 4 ]
    assert_has "file.txt"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]
    [ "$(git -C "$TEST_WORKTREES/WT" status --porcelain)" = " M file.txt" ]
    [ ! -d "$TRASH_DIR" ] || [ -z "$(ls -A "$TRASH_DIR")" ]
}

@test "patch apply refuses when the index has staged changes" {
    _create_wt WT
    _make_change
    echo "staged" >|"$TEST_WORKTREES/WT/staged.txt"
    git -C "$TEST_WORKTREES/WT" add staged.txt
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 4 ]
    assert_has "staged.txt"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]
}

@test "patch apply does not block on edits to files the patch leaves alone" {
    _create_wt WT
    _make_change
    cd "$TEST_WORKTREES/WT"
    echo "mine" >|mine.txt
    git add mine.txt
    git commit -q -m "mine"
    echo "edited" >>mine.txt
    echo "scratch" >|scratch.txt
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    [ "$(_wt_commit_count WT)" -eq 5 ]
    [ "$(git -C "$TEST_WORKTREES/WT" status --porcelain | sort | tr '\n' '|')" = " M mine.txt|?? scratch.txt|" ]
}

@test "patch apply refuses when the patch creates a file that exists untracked" {
    _create_wt WT
    _make_change
    echo "already here" >|"$TEST_WORKTREES/WT/g.txt"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 4 ]
    assert_has "g.txt"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]
    [ "$(cat "$TEST_WORKTREES/WT/g.txt")" = "already here" ]
}

@test "patch apply refuses a detached HEAD unless --detached" {
    _create_wt WT
    _make_change
    git -C "$TEST_WORKTREES/WT" checkout -q --detach
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 4 ]
    assert_has "--detached"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]

    run "$PWT_BIN" patch apply WT "$MBOX" --detached
    [ "$status" -eq 0 ]
    [ "$(_wt_commit_count WT)" -eq 4 ]
}

@test "patch apply refuses while an am or rebase is in progress" {
    _create_wt WT
    _make_change
    # git marks a running `am` with rebase-apply/applying
    local gitdir
    gitdir=$(git -C "$TEST_WORKTREES/WT" rev-parse --absolute-git-dir)
    mkdir -p "$gitdir/rebase-apply"
    : >|"$gitdir/rebase-apply/applying"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 4 ]
    assert_has "git am --abort"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]
}

@test "patch apply refuses a message with a session trailer unless --strip-session" {
    _create_wt WT
    cd "$TEST_REPO"
    git checkout -q -b change
    echo "x" >|x.txt
    git add x.txt
    # The trailer the command must refuse, assembled from parts so the
    # fixture never spells it out in one piece
    local trailer="Agent-Sess"
    trailer="${trailer}ion: 0123abcd"
    local link="https://example.com/code/sess"
    link="${link}ion/0123abcd"
    _commit_as_change_author -m "add x

${trailer}
See ${link}"
    git format-patch --stdout "$DEFAULT_BRANCH"..change >|"$MBOX"
    git checkout -q "$DEFAULT_BRANCH"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 4 ]
    assert_has "--strip-session"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]

    run "$PWT_BIN" patch apply WT "$MBOX" --strip-session
    [ "$status" -eq 0 ]
    [ "$(_wt_commit_count WT)" -eq 3 ]
    local body
    body=$(git -C "$TEST_WORKTREES/WT" log -1 --format=%B)
    case "$body" in
        *"Sess"*) echo "trailer survived: $body" >&2; return 1 ;;
    esac
    case "$body" in
        *"add x"*) ;;
        *) echo "subject lost: $body" >&2; return 1 ;;
    esac
}

@test "patch apply refuses a patch that touches a secret path unless --allow-secrets" {
    _create_wt WT
    cd "$TEST_REPO"
    git checkout -q -b change
    echo "TOKEN=1" >|.env
    git add -f .env
    _commit_as_change_author -m "add env"
    git format-patch --stdout "$DEFAULT_BRANCH"..change >|"$MBOX"
    git checkout -q "$DEFAULT_BRANCH"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 4 ]
    assert_has ".env"
    assert_has "--allow-secrets"
    [ ! -f "$TEST_WORKTREES/WT/.env" ]

    run "$PWT_BIN" patch apply WT "$MBOX" --allow-secrets
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORKTREES/WT/.env" ]
}

@test "patch apply --idle refuses while a pwt job runs for the worktree" {
    _create_wt WT
    _make_change
    sleep 60 &
    SLEEP_PID=$!
    mkdir -p "$PWT_DIR/jobs"
    cat >|"$PWT_DIR/jobs/job-test.job" <<EOF
id=job-test
pid=$SLEEP_PID
pgid=$SLEEP_PID
command=server
worktree=WT
project=test-project
log=$TEST_TEMP_DIR/job.log
started_at=2026-01-01T00:00:00Z
started_epoch=1
status=running
EOF
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX" --idle
    [ "$status" -eq 4 ]
    assert_has "job-test"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]

    # Without --idle the job is a warning and the apply goes ahead
    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    assert_has "job-test"
    [ "$(_wt_commit_count WT)" -eq 4 ]
}

# ============================================
# apply: conflict aborts and leaves the worktree as it was
# ============================================

@test "patch apply aborts on conflict with HEAD and tree unchanged" {
    _create_wt WT
    _make_change
    cd "$TEST_WORKTREES/WT"
    printf 'content\nX\n' >|file.txt
    git commit -q -am "conflicting"
    local before
    before=$(git rev-parse HEAD)
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 1 ]
    assert_has "file.txt"
    [ "$(_wt_head WT)" = "$before" ]
    [ "$(git -C "$TEST_WORKTREES/WT" status --porcelain | wc -l | tr -d ' ')" -eq 0 ]
    [ ! -d "$(git -C "$TEST_WORKTREES/WT" rev-parse --absolute-git-dir)/rebase-apply" ]
}

@test "patch apply of a patch from an unrelated repository does not leave a half state" {
    _create_wt WT
    local other="$TEST_TEMP_DIR/other"
    git init -q "$other"
    git -C "$other" config user.email "o@example.com"
    git -C "$other" config user.name "Other"
    printf 'something else\n' >|"$other/file.txt"
    git -C "$other" add file.txt
    git -C "$other" commit -q -m "other base"
    printf 'something else\nmore\n' >|"$other/file.txt"
    git -C "$other" commit -q -am "other change"
    git -C "$other" format-patch --stdout HEAD~1..HEAD >|"$MBOX"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 1 ]
    [ "$(_wt_head WT)" = "$BASE_SHA" ]
    [ "$(git -C "$TEST_WORKTREES/WT" status --porcelain | wc -l | tr -d ' ')" -eq 0 ]
}

# ============================================
# apply: backup to the trash, undo, restore listing
# ============================================

@test "patch apply writes a trash record with the HEAD before the apply" {
    _create_wt WT
    _make_change
    echo "kept" >|"$TEST_WORKTREES/WT/README.md"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    local record
    record=$(ls "$TRASH_DIR"/WT_*.trash)
    [ -f "$record" ]
    grep -q "^head=$BASE_SHA$" "$record"
    grep -q "^kind=patch-apply$" "$record"
    # the local edit was saved as a patch and is still in the tree
    [ -f "${record%.trash}.patch" ]
    [ "$(cat "$TEST_WORKTREES/WT/README.md")" = "kept" ]

    run "$PWT_BIN" restore
    [ "$status" -eq 0 ]
    assert_has "WT"
    assert_has "${BASE_SHA%${BASE_SHA#???????}}"
}

@test "patch apply on a clean tree records the HEAD and writes no patch" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"

    "$PWT_BIN" patch apply WT "$MBOX" >/dev/null
    local record
    record=$(ls "$TRASH_DIR"/WT_*.trash)
    grep -q "^head=$BASE_SHA$" "$record"
    [ ! -f "${record%.trash}.patch" ]
}

# ============================================
# apply: a plain diff changes files and makes no commit
# ============================================

@test "patch apply of a plain diff edits the files without committing" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"
    git diff "$DEFAULT_BRANCH" change >|"$TEST_TEMP_DIR/plain.diff"

    run "$PWT_BIN" patch apply WT "$TEST_TEMP_DIR/plain.diff"
    [ "$status" -eq 0 ]
    assert_has "no commit"
    [ "$(_wt_head WT)" = "$BASE_SHA" ]
    [ "$(git -C "$TEST_WORKTREES/WT" status --porcelain | sort | tr '\n' '|')" = " M file.txt|?? g.txt|" ]
}

@test "patch apply of a plain diff refuses local edits on touched files" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"
    git diff "$DEFAULT_BRANCH" change >|"$TEST_TEMP_DIR/plain.diff"
    echo "local" >>"$TEST_WORKTREES/WT/file.txt"

    run "$PWT_BIN" patch apply WT "$TEST_TEMP_DIR/plain.diff"
    [ "$status" -eq 4 ]
    assert_has "file.txt"
}

# ============================================
# apply: what the Pwtfile sees afterwards
# ============================================

@test "patch apply suggests repair and runs it only with --repair" {
    _create_wt WT
    _make_change
    cat >|"$TEST_REPO/Pwtfile" <<'EOF'
repair() {
    printf '%s\n' "$PWT_CHANGED_FILES" >| "$PWT_WORKTREE_PATH/repair.log"
    printf '%s\n' "$PWT_PREVIOUS_COMMIT" >> "$PWT_WORKTREE_PATH/repair.log"
}
EOF
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    assert_has "pwt repair WT"
    [ ! -f "$TEST_WORKTREES/WT/repair.log" ]

    git -C "$TEST_WORKTREES/WT" reset -q --keep "$BASE_SHA"
    run "$PWT_BIN" patch apply WT "$MBOX" --repair
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORKTREES/WT/repair.log" ]
    grep -q "^file.txt$" "$TEST_WORKTREES/WT/repair.log"
    grep -q "^g.txt$" "$TEST_WORKTREES/WT/repair.log"
    grep -q "^$BASE_SHA$" "$TEST_WORKTREES/WT/repair.log"
}

# ============================================
# apply: --json
# ============================================

@test "patch apply --json reports the result for tools" {
    _create_wt WT
    _make_change
    cd "$TEST_REPO"

    # stderr carries the prose; stdout must be the one JSON line
    run bash -c '"$0" patch apply WT "$1" --json 2>/dev/null' "$PWT_BIN" "$MBOX"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    assert_has '"schema_version":1'
    assert_has '"result":"applied"'
    assert_has '"head_before":"'"$BASE_SHA"'"'
    assert_has '"subject":"add d"'
    assert_has '"skipped":0'
    assert_has '"touched_files":["file.txt","g.txt"]'

    # The third change touches g.txt, which now has a local edit
    echo "local" >>"$TEST_WORKTREES/WT/g.txt"
    _extend_change
    cd "$TEST_REPO"
    run "$PWT_BIN" patch apply WT "$MBOX" --json
    [ "$status" -eq 4 ]
    assert_has '"result":"refused"'
    assert_has '"reason":"local edits on touched files"'
}

@test "patch apply --json on a conflict reports aborted and the files" {
    _create_wt WT
    _make_change
    cd "$TEST_WORKTREES/WT"
    printf 'content\nX\n' >|file.txt
    git commit -q -am "conflicting"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX" --json
    [ "$status" -eq 1 ]
    assert_has '"result":"aborted"'
    assert_has '"conflict_files":["file.txt"]'
}

# ============================================
# apply: content the patch may carry
# ============================================

@test "patch apply keeps a typechange to a symlink and a binary file" {
    _create_wt WT
    cd "$TEST_REPO"
    git checkout -q -b change
    rm file.txt
    ln -s README.md file.txt
    printf '\000\001\002\003' >|blob.bin
    git add -A
    _commit_as_change_author -m "symlink and binary"
    git format-patch --stdout --binary "$DEFAULT_BRANCH"..change >|"$MBOX"
    git checkout -q "$DEFAULT_BRANCH"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    [ -L "$TEST_WORKTREES/WT/file.txt" ]
    [ "$(od -An -tx1 "$TEST_WORKTREES/WT/blob.bin" | tr -d ' \n')" = "00010203" ]
}

@test "patch apply names the files that needed a 3-way merge" {
    # A base long enough for the patch's context to miss: the worktree
    # rewrites a context line, so the plain apply fails and the 3-way
    # merge resolves it (the two changes do not touch)
    cd "$TEST_REPO"
    printf 'l1\nl2\nl3\nl4\nl5\ncontent\n' >|file.txt
    git commit -q -am "longer base"
    BASE_SHA=$(git rev-parse HEAD)
    _create_wt WT
    git checkout -q -b change
    printf 'l1\nl2\nl3\nl4\nl5\ncontent\nd\n' >|file.txt
    _commit_as_change_author -am "add d"
    git format-patch --stdout "$DEFAULT_BRANCH"..change >|"$MBOX"
    git checkout -q "$DEFAULT_BRANCH"
    cd "$TEST_WORKTREES/WT"
    printf 'l1\nl2\nl3\nl4\nL5\ncontent\n' >|file.txt
    git commit -q -am "rewrite l5"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch apply WT "$MBOX"
    [ "$status" -eq 0 ]
    assert_has "3-way"
    assert_has "file.txt"
    [ "$(tr '\n' '|' <"$TEST_WORKTREES/WT/file.txt")" = "l1|l2|l3|l4|L5|content|d|" ]
}

# ============================================
# export
# ============================================

@test "patch export writes the worktree's own commits as a mailbox" {
    _create_wt WT
    cd "$TEST_WORKTREES/WT"
    echo "one" >|one.txt
    git add one.txt
    git commit -q -m "one"
    echo "two" >|two.txt
    git add two.txt
    git commit -q -m "two"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch export WT -o "$TEST_TEMP_DIR/wt.patch"
    [ "$status" -eq 0 ]
    assert_has "2 commits"
    [ -f "$TEST_TEMP_DIR/wt.patch" ]
    grep -q "^Subject: \[PATCH 1/2\] one" "$TEST_TEMP_DIR/wt.patch"

    _create_wt OTHER
    run "$PWT_BIN" patch apply OTHER "$TEST_TEMP_DIR/wt.patch"
    [ "$status" -eq 0 ]
    [ "$(_wt_commit_count OTHER)" -eq 4 ]
}

@test "patch export to stdout keeps the mailbox clean and the count on stderr" {
    _create_wt WT
    cd "$TEST_WORKTREES/WT"
    echo "one" >|one.txt
    git add one.txt
    git commit -q -m "one"
    cd "$TEST_REPO"

    "$PWT_BIN" patch export WT >|"$TEST_TEMP_DIR/out.patch" 2>|"$TEST_TEMP_DIR/err.txt"
    [ "$(head -c 5 "$TEST_TEMP_DIR/out.patch")" = "From " ]
    grep -q "1 commit" "$TEST_TEMP_DIR/err.txt"

    _create_wt OTHER
    "$PWT_BIN" patch apply OTHER - <"$TEST_TEMP_DIR/out.patch" >/dev/null
    [ "$(_wt_commit_count OTHER)" -eq 3 ]
}

@test "patch export --base takes an explicit range start" {
    _create_wt WT
    cd "$TEST_WORKTREES/WT"
    echo "one" >|one.txt
    git add one.txt
    git commit -q -m "one"
    local mid
    mid=$(git rev-parse HEAD)
    echo "two" >|two.txt
    git add two.txt
    git commit -q -m "two"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch export WT --base "$mid" -o "$TEST_TEMP_DIR/wt.patch"
    [ "$status" -eq 0 ]
    assert_has "1 commit"
    grep -q "^Subject: \[PATCH\] two" "$TEST_TEMP_DIR/wt.patch"
}

@test "patch export with nothing to export writes no file and says so" {
    _create_wt WT
    cd "$TEST_REPO"

    run "$PWT_BIN" patch export WT -o "$TEST_TEMP_DIR/wt.patch"
    [ "$status" -eq 0 ]
    assert_has "0 commits"
    [ ! -f "$TEST_TEMP_DIR/wt.patch" ]
}

@test "patch export warns when the range has merge commits" {
    _create_wt WT
    _make_change
    cd "$TEST_WORKTREES/WT"
    echo "one" >|one.txt
    git add one.txt
    git commit -q -m "one"
    git merge -q --no-ff -m "merge change" change
    cd "$TEST_REPO"

    run "$PWT_BIN" patch export WT -o "$TEST_TEMP_DIR/wt.patch"
    [ "$status" -eq 0 ]
    assert_has "merge"
}

@test "patch export --json reports base, count and output" {
    _create_wt WT
    cd "$TEST_WORKTREES/WT"
    echo "one" >|one.txt
    git add one.txt
    git commit -q -m "one"
    cd "$TEST_REPO"

    run "$PWT_BIN" patch export WT -o "$TEST_TEMP_DIR/wt.patch" --json
    [ "$status" -eq 0 ]
    assert_has '"command":"patch export"'
    assert_has '"commits":1'
    assert_has '"base":"'"$BASE_SHA"'"'
}

# ============================================
# help and usage
# ============================================

@test "patch --help and patch with no action show usage" {
    run "$PWT_BIN" patch --help
    [ "$status" -eq 0 ]
    assert_has "patch apply"
    assert_has "patch export"

    cd "$TEST_REPO"
    run "$PWT_BIN" patch
    [ "$status" -eq 2 ]
    assert_has "Usage"
}

@test "pwt help lists patch apply and export" {
    run "$PWT_BIN" help
    assert_has "patch apply"
    assert_has "patch export"
}
