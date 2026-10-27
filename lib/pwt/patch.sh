#!/usr/bin/env bash
# pwt module: patch
#
# `pwt patch apply`: commits made somewhere else (a change tool, a teammate,
# another agent's worktree) land on a worktree as commits, or nothing
# changes. `pwt patch export`: a worktree's own commits as one mailbox.
#
# Loaded on demand with `load_module patch`. Needs the project context
# (require_project) and the shared helpers of bin/pwt: resolve_worktree_path,
# get_metadata, get_current_from_symlink, state_get, _state_escape,
# json_escape, has_pwtfile_command, run_pwtfile, pwt_error, EXIT_*.

# Patches above this size are refused before anything is read into git
PWT_PATCH_MAX_BYTES="${PWT_PATCH_MAX_BYTES:-52428800}"

# Paths a patch may not touch without --allow-secrets: one glob per word,
# matched against the path and against its basename
PWT_PATCH_SECRET_GLOBS="${PWT_PATCH_SECRET_GLOBS:-.env .env.* *.pem *.key *credentials* *secret* id_rsa* id_ed25519*}"

# A commit message line that attributes the commit to an agent session.
# `git am` would carry it into the branch; the owner of the worktree may
# not want that on record.
PWT_PATCH_SESSION_RE='^[A-Za-z-]*Session:|://[^ ]*/session/'

_patch_usage() {
	cat <<'EOF'
Usage: pwt patch apply [<worktree>] <file|->  [options]
       pwt patch export [<worktree>] [--base <ref>] [-o <file>] [--json]

Land commits from a patch file on a worktree, or export a worktree's commits
as a patch file. Without <worktree>, the worktree you stand in is used.

apply reads a mailbox (git format-patch output, applied with git am -3) or
a plain diff (applied to the files with git apply, no commit). It refuses,
with nothing changed, when:
  - a touched file has local edits, or the index has staged changes
  - an am, rebase, merge, cherry-pick, revert or bisect is in progress
  - HEAD is detached                       (override: --detached)
  - a commit message carries a session trailer or link
                                           (override: --strip-session)
  - the patch touches a secret path (.env, *.pem, *.key, ...)
                                           (override: --allow-secrets)
  - a pwt job runs for the worktree and --idle was given
Patches the branch already has (same patch-id) are skipped. The HEAD before
the apply and any local edits go to ~/.pwt/trash first (pwt restore lists
them). On a conflict the apply is aborted and the worktree is left as it was.

apply options:
  --json            One JSON object on stdout for tools
  --repair          Run the Pwtfile's repair() afterwards (it sees
                    PWT_CHANGED_FILES and PWT_PREVIOUS_COMMIT)
  --idle            Refuse while a pwt job runs for the worktree
  --detached        Apply on a detached HEAD
  --strip-session   Drop session trailers and links from the messages
  --allow-secrets   Let the patch touch secret paths
  -p<n>             Strip <n> leading path components (plain diffs)

export options:
  --base <ref>      Range start (default: merge base with the worktree's
                    recorded base branch)
  -o <file>         Write here instead of stdout
  --json            One JSON object on stdout (needs -o)

Exit codes: 0 applied or exported (commits already in the branch count as
applied: skipped), 1 aborted on conflict or git error, 2 usage, 3 worktree
or file not found, 4 refused before any change.

Examples:
  pwt patch apply TICKET-123 ~/Downloads/fix.patch
  curl -s "$URL" | pwt patch apply TICKET-123 -
  pwt agent-wt patch export | pwt my-wt patch apply -
  pwt patch export TICKET-123 -o TICKET-123.patch
EOF
}

# Say something to the person. With --json stdout is the object, so the
# prose goes to stderr.
_patch_say() {
	if [ "$_PATCH_JSON" = true ]; then
		echo -e "$*" >&2
	else
		echo -e "$*"
	fi
}

# ["a","b"] from a newline-separated list
_patch_json_lines() {
	local out="" line
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		out="${out:+$out,}\"$(json_escape "$line")\""
	done <<<"$1"
	printf '[%s]' "$out"
}

cmd_patch() {
	_PATCH_JSON=false
	_PATCH_REPAIR=false
	_PATCH_IDLE=false
	_PATCH_DETACHED=false
	_PATCH_STRIP=false
	_PATCH_ALLOW_SECRETS=false
	_PATCH_PLEVEL=""
	_PATCH_BASE=""
	_PATCH_OUT=""
	_PATCH_TMPDIR=""

	local action=""
	local -a positional=()
	while [ $# -gt 0 ]; do
		case "$1" in
		apply | export)
			if [ -z "$action" ]; then
				action="$1"
			else
				positional+=("$1")
			fi
			;;
		-h | --help)
			_patch_usage
			return 0
			;;
		--json) _PATCH_JSON=true ;;
		--repair) _PATCH_REPAIR=true ;;
		--idle) _PATCH_IDLE=true ;;
		--detached) _PATCH_DETACHED=true ;;
		--strip-session) _PATCH_STRIP=true ;;
		--allow-secrets) _PATCH_ALLOW_SECRETS=true ;;
		-p[0-9]*) _PATCH_PLEVEL="$1" ;;
		--base)
			shift
			_PATCH_BASE="${1:-}"
			if [ -z "$_PATCH_BASE" ]; then
				pwt_error "Error: --base needs a ref"
				return $EXIT_USAGE
			fi
			;;
		--base=*) _PATCH_BASE="${1#--base=}" ;;
		-o | --output)
			shift
			_PATCH_OUT="${1:-}"
			if [ -z "$_PATCH_OUT" ]; then
				pwt_error "Error: -o needs a file"
				return $EXIT_USAGE
			fi
			;;
		-o=* | --output=*) _PATCH_OUT="${1#*=}" ;;
		--)
			shift
			while [ $# -gt 0 ]; do
				positional+=("$1")
				shift
			done
			break
			;;
		-) positional+=("-") ;;
		-*)
			pwt_error "Error: Unknown option: $1"
			echo "Run 'pwt patch --help' for usage" >&2
			return $EXIT_USAGE
			;;
		*) positional+=("$1") ;;
		esac
		shift
	done

	if [ -z "$action" ]; then
		_patch_usage >&2
		return $EXIT_USAGE
	fi

	_PATCH_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/pwt-patch.XXXXXX") || {
		pwt_error "Error: cannot create a temp dir"
		return $EXIT_ERROR
	}
	local rc=0
	if [ ${#positional[@]} -gt 0 ]; then
		"_patch_$action" "${positional[@]}" || rc=$?
	else
		"_patch_$action" || rc=$?
	fi
	rm -rf "$_PATCH_TMPDIR"
	return $rc
}

# Sets PATCH_WT_NAME and PATCH_WT_PATH. Empty target: the worktree the
# shell stands in, else the current symlink (as `pwt logs` does).
_patch_resolve_worktree() {
	local target="${1:-}"
	if [ -z "$target" ]; then
		local cur_dir resolved_wt_dir=""
		cur_dir=$(pwd -P)
		if [ -n "${WORKTREES_DIR:-}" ] && [ -d "$WORKTREES_DIR" ]; then
			resolved_wt_dir=$(cd "$WORKTREES_DIR" && pwd -P)
		fi
		if [ -n "$resolved_wt_dir" ] && [ "${cur_dir#"$resolved_wt_dir"/}" != "$cur_dir" ]; then
			target="${cur_dir#"$resolved_wt_dir"/}"
			target="${target%%/*}"
		else
			target=$(get_current_from_symlink 2>/dev/null || echo "")
		fi
	fi
	target="${target%/}"
	if [ -z "$target" ]; then
		pwt_error "Error: No worktree specified or detected"
		echo "Usage: pwt patch apply <worktree> <file|->" >&2
		return $EXIT_USAGE
	fi
	if [ "$target" = "@" ]; then
		PATCH_WT_NAME="@"
		PATCH_WT_PATH="$MAIN_APP"
		return 0
	fi
	local path
	path=$(resolve_worktree_path "$target" 2>/dev/null) || path=""
	if [ -z "$path" ] || [ ! -d "$path" ]; then
		pwt_error "Error: Worktree not found: $target"
		return $EXIT_NOT_FOUND
	fi
	PATCH_WT_NAME=$(basename "$path")
	PATCH_WT_PATH="$path"
	return 0
}

# Ids of the pwt jobs running for a worktree, space-separated (the loop
# `pwt repoint` uses before it rewrites files)
_patch_running_jobs() {
	local name="$1" f running="" jid
	load_module jobs
	for f in "${PWT_JOBS_DIR:-$PWT_DIR/jobs}"/*.job; do
		[ -f "$f" ] || continue
		[ "$(state_get "$f" "project")" = "$CURRENT_PROJECT" ] || continue
		[ "$(state_get "$f" "worktree")" = "$name" ] || continue
		[ "$(state_get "$f" "status")" = running ] || continue
		jid=$(state_get "$f" "id")
		_is_job_alive "$jid" && running="${running:+$running }$jid"
	done
	printf '%s' "$running"
}

# Is $1 one of the newline-separated entries in $2?
_patch_in_list() {
	case "$2" in
	"$1" | "$1"$'\n'* | *$'\n'"$1" | *$'\n'"$1"$'\n'*) return 0 ;;
	esac
	return 1
}

# The trash record `pwt restore` lists: the HEAD to go back to, plus a
# patch of the tracked local edits when there are any (git diff, never a
# stash: a stash in a pwt worktree has popped another branch's backup
# before). Sets PATCH_BACKUP_NAME.
_patch_backup() {
	local name="$1" path="$2" head="$3"
	local backup_dir="$PWT_DIR/trash"
	mkdir -p "$backup_dir"
	local ts bn i=1
	ts=$(date +%Y%m%d_%H%M%S)
	bn="${name}_${ts}"
	while [ -e "$backup_dir/$bn.trash" ]; do
		bn="${name}_${ts}_$i"
		i=$((i + 1))
	done
	local branch base port desc
	branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
	base=$(get_metadata "$name" "base" 2>/dev/null || echo "")
	port=$(get_metadata "$name" "port" 2>/dev/null || echo "")
	desc=$(get_metadata "$name" "description" 2>/dev/null || echo "")
	{
		printf 'worktree=%s\n' "$(_state_escape "$name")"
		printf 'branch=%s\n' "$(_state_escape "$branch")"
		printf 'base=%s\n' "$(_state_escape "$base")"
		printf 'port=%s\n' "$port"
		printf 'description=%s\n' "$(_state_escape "$desc")"
		printf 'project=%s\n' "$(_state_escape "$CURRENT_PROJECT")"
		printf 'timestamp=%s\n' "$ts"
		printf 'date=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
		printf 'kind=patch-apply\n'
		printf 'head=%s\n' "$head"
	} >"$backup_dir/$bn.trash"
	if ! git -C "$path" diff --quiet HEAD -- 2>/dev/null; then
		git -C "$path" diff --binary HEAD -- >"$backup_dir/$bn.patch" 2>/dev/null
		[ -s "$backup_dir/$bn.patch" ] || rm -f "$backup_dir/$bn.patch"
	fi
	PATCH_BACKUP_NAME="$bn"
}

# Drop session trailers and links from the message of one mailsplit piece:
# the body runs from the first blank line to the `---` that opens the diff.
_patch_strip_session() {
	awk -v re="$PWT_PATCH_SESSION_RE" '
		BEGIN { s = 0 }
		s == 0 { print; if ($0 == "") s = 1; next }
		s == 1 {
			if ($0 == "---") { s = 2; print; next }
			if ($0 ~ re) next
			print; next
		}
		{ print }
	' "$1"
}

# One JSON object for `patch apply --json`. Arguments are newline lists
# where they are lists.
_patch_emit_apply_json() {
	local result="$1" reason="$2" head_before="$3" head_after="$4" applied="$5" skipped="$6"
	local touched="$7" three_way="$8" conflicts="$9" backup="${10}" undo="${11}" repair="${12}"
	local applied_json="" line sha subject
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		sha="${line%% *}"
		subject="${line#* }"
		[ "$subject" = "$line" ] && subject=""
		applied_json="${applied_json:+$applied_json,}{\"sha\":\"$sha\",\"subject\":\"$(json_escape "$subject")\"}"
	done <<<"$applied"
	printf '{"schema_version":1,"command":"patch apply","project":"%s","worktree":"%s","path":"%s","kind":"%s","result":"%s","reason":"%s","head_before":"%s","head_after":"%s","applied":[%s],"skipped":%s,"touched_files":%s,"three_way_files":%s,"conflict_files":%s,"backup":"%s","undo":"%s","repair_available":%s}\n' \
		"$(json_escape "$CURRENT_PROJECT")" "$(json_escape "$PATCH_WT_NAME")" "$(json_escape "$PATCH_WT_PATH")" \
		"$_PATCH_KIND" "$result" "$(json_escape "$reason")" "$head_before" "$head_after" \
		"$applied_json" "$skipped" "$(_patch_json_lines "$touched")" "$(_patch_json_lines "$three_way")" \
		"$(_patch_json_lines "$conflicts")" "$(json_escape "$backup")" "$(json_escape "$undo")" "$repair"
}

# A refusal: nothing was changed. $1 short reason (the JSON `reason`), the
# rest are detail lines for the person.
_patch_refuse() {
	local reason="$1"
	shift
	pwt_error "Refused: $reason"
	local line
	for line in "$@"; do
		echo "  $line" >&2
	done
	if [ "$_PATCH_JSON" = true ]; then
		_patch_emit_apply_json refused "$reason" "$_PATCH_HEAD_BEFORE" "$_PATCH_HEAD_BEFORE" "" 0 "$_PATCH_TOUCHED" "" "" "" "" false
	fi
	return $EXIT_CONFLICT
}

_patch_apply() {
	local wt="" input=""
	case $# in
	0)
		pwt_error "Error: patch apply needs a patch file, or - for stdin"
		echo "Usage: pwt patch apply [<worktree>] <file|->" >&2
		return $EXIT_USAGE
		;;
	1) input="$1" ;;
	2)
		wt="$1"
		input="$2"
		;;
	*)
		pwt_error "Error: too many arguments"
		echo "Usage: pwt patch apply [<worktree>] <file|->" >&2
		return $EXIT_USAGE
		;;
	esac
	_patch_resolve_worktree "$wt" || return $?
	local name="$PATCH_WT_NAME" path="$PATCH_WT_PATH" tmp="$_PATCH_TMPDIR"
	_PATCH_KIND=""
	_PATCH_TOUCHED=""
	_PATCH_HEAD_BEFORE=""

	# ---- the input ---------------------------------------------------
	local patch_file="$tmp/input.patch"
	if [ "$input" = "-" ]; then
		cat >"$patch_file"
	else
		if [ ! -f "$input" ]; then
			pwt_error "Error: Patch file not found: $input"
			return $EXIT_NOT_FOUND
		fi
		cp "$input" "$patch_file"
	fi
	local size
	size=$(wc -c <"$patch_file" | tr -d ' ')
	if [ "$size" -eq 0 ]; then
		pwt_error "Error: the patch input is empty"
		echo "Usage: pwt patch apply [<worktree>] <file|->" >&2
		return $EXIT_USAGE
	fi
	if [ "$size" -gt "$PWT_PATCH_MAX_BYTES" ]; then
		pwt_error "Error: the patch is $size bytes, above PWT_PATCH_MAX_BYTES ($PWT_PATCH_MAX_BYTES)"
		return $EXIT_USAGE
	fi
	local first_line
	first_line=$(head -n 1 "$patch_file")
	case "$first_line" in
	"From "[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*" "*) _PATCH_KIND=mailbox ;;
	*)
		if grep -q -E '^(diff --git |--- |Index: )' "$patch_file"; then
			_PATCH_KIND=diff
		else
			pwt_error "Error: not a patch: expected a git format-patch mailbox or a diff"
			return $EXIT_USAGE
		fi
		;;
	esac

	# ---- the worktree before anything happens -------------------------
	local head_before
	head_before=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null) || {
		pwt_error "Error: $name has no commits to apply onto"
		return $EXIT_ERROR
	}
	_PATCH_HEAD_BEFORE="$head_before"
	local gitdir
	gitdir=$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null) ||
		gitdir=$(cd "$path" && git rev-parse --git-dir 2>/dev/null)
	case "$gitdir" in
	/*) ;;
	*) gitdir="$path/$gitdir" ;;
	esac

	local op="" abort=""
	if [ -d "$gitdir/rebase-apply" ]; then
		if [ -f "$gitdir/rebase-apply/applying" ]; then
			op="git am"
			abort="git am --abort"
		else
			op="rebase"
			abort="git rebase --abort"
		fi
	elif [ -d "$gitdir/rebase-merge" ]; then
		op="rebase"
		abort="git rebase --abort"
	elif [ -f "$gitdir/MERGE_HEAD" ]; then
		op="merge"
		abort="git merge --abort"
	elif [ -f "$gitdir/CHERRY_PICK_HEAD" ]; then
		op="cherry-pick"
		abort="git cherry-pick --abort"
	elif [ -f "$gitdir/REVERT_HEAD" ]; then
		op="revert"
		abort="git revert --abort"
	elif [ -f "$gitdir/BISECT_LOG" ]; then
		op="bisect"
		abort="git bisect reset"
	fi
	if [ -n "$op" ]; then
		_patch_refuse "$op in progress" "Finish it, or go back with: git -C $path $abort"
		return $?
	fi

	if ! git -C "$path" symbolic-ref -q HEAD >/dev/null 2>&1; then
		if [ "$_PATCH_DETACHED" != true ]; then
			_patch_refuse "detached HEAD" \
				"Commits on a detached HEAD belong to no branch." \
				"Check out a branch first, or pass --detached to apply here anyway."
			return $?
		fi
	fi

	local staged
	staged=$(git -C "$path" diff --cached --name-only 2>/dev/null)
	if [ -n "$staged" ]; then
		_patch_refuse "staged changes in the index" \
			"git am would fold them into the first commit. Commit or unstage:" \
			"$(echo "$staged" | sed 's/^/  /')"
		return $?
	fi

	# ---- which patches, which files -----------------------------------
	local apply_file="$patch_file" skipped=0 subjects=""
	if [ "$_PATCH_KIND" = mailbox ]; then
		local split="$tmp/split"
		mkdir -p "$split"
		if ! git mailsplit -o"$split" "$patch_file" >/dev/null 2>&1; then
			pwt_error "Error: cannot split the mailbox (is it git format-patch output?)"
			return $EXIT_USAGE
		fi

		# Patch-ids of what the branch already has, since its base
		local base_ref local_ids=""
		base_ref=$(get_metadata "$name" "base" 2>/dev/null || echo "")
		[ -n "$base_ref" ] || base_ref="${DEFAULT_BRANCH:-master}"
		local mb
		if mb=$(git -C "$path" merge-base HEAD "$base_ref" 2>/dev/null) && [ -n "$mb" ]; then
			local_ids=$(git -C "$path" rev-list --no-merges "$mb..HEAD" 2>/dev/null |
				git -C "$path" diff-tree -p --stdin 2>/dev/null |
				git -C "$path" patch-id --stable 2>/dev/null | cut -d' ' -f1)
		else
			local_ids=$(git -C "$path" rev-list --no-merges --max-count=500 HEAD 2>/dev/null |
				git -C "$path" diff-tree -p --stdin 2>/dev/null |
				git -C "$path" patch-id --stable 2>/dev/null | cut -d' ' -f1)
		fi

		local piece subject id trailer_hits="" keep=""
		for piece in "$split"/*; do
			[ -f "$piece" ] || continue
			git mailinfo "$tmp/msg" "$tmp/diff" <"$piece" >"$tmp/info" 2>/dev/null || true
			subject=$(sed -n 's/^Subject: //p' "$tmp/info" | head -n 1)
			id=$(git patch-id --stable <"$tmp/diff" 2>/dev/null | cut -d' ' -f1)
			if [ -z "$id" ]; then
				# No diff in this message: nothing to apply, nothing to merge
				skipped=$((skipped + 1))
				continue
			fi
			if _patch_in_list "$id" "$local_ids"; then
				skipped=$((skipped + 1))
				continue
			fi
			if grep -q -E "$PWT_PATCH_SESSION_RE" "$tmp/msg" 2>/dev/null ||
				printf '%s\n' "$subject" | grep -q -E "$PWT_PATCH_SESSION_RE"; then
				trailer_hits="${trailer_hits:+$trailer_hits$'\n'}$subject"
			fi
			subjects="${subjects:+$subjects$'\n'}$subject"
			keep="${keep:+$keep$'\n'}$piece"
		done

		if [ -z "$keep" ]; then
			_patch_say "${YELLOW}Nothing to apply to $name: skipped $skipped (already in branch)${NC}"
			if [ "$_PATCH_JSON" = true ]; then
				_patch_emit_apply_json applied "nothing to apply" "$head_before" "$head_before" "" "$skipped" "" "" "" "" "" false
			fi
			return 0
		fi

		if [ -n "$trailer_hits" ]; then
			if [ "$_PATCH_STRIP" != true ]; then
				_patch_refuse "session trailers in commit messages" \
					"These messages carry a session trailer or link:" \
					"$(echo "$trailer_hits" | sed 's/^/  /')" \
					"Pass --strip-session to apply them without those lines."
				return $?
			fi
		fi

		apply_file="$tmp/apply.mbox"
		: >"$apply_file"
		while IFS= read -r piece; do
			[ -n "$piece" ] || continue
			if [ "$_PATCH_STRIP" = true ]; then
				_patch_strip_session "$piece" >>"$apply_file"
			else
				cat "$piece" >>"$apply_file"
			fi
		done <<<"$keep"
	fi

	local touched creates
	touched=$(git -C "$path" apply --numstat $_PATCH_PLEVEL "$apply_file" 2>/dev/null | awk -F'\t' '{ print $3 }' | awk '!seen[$0]++')
	creates=$(git -C "$path" apply --summary $_PATCH_PLEVEL "$apply_file" 2>/dev/null | sed -n 's/^ create mode [0-7]* //p')
	_PATCH_TOUCHED="$touched"
	if [ -z "$touched" ]; then
		pwt_error "Error: git cannot read a diff out of this patch"
		git -C "$path" apply --numstat $_PATCH_PLEVEL "$apply_file" 2>&1 | head -n 5 | sed 's/^/  /' >&2
		return $EXIT_USAGE
	fi

	# Local edits on the files the patch rewrites. Edits elsewhere stay
	# where they are and do not block.
	local dirty blocked="" f
	dirty=$(git -C "$path" status --porcelain --untracked-files=no 2>/dev/null | cut -c4-)
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		_patch_in_list "$f" "$dirty" && blocked="${blocked:+$blocked$'\n'}$f"
	done <<<"$touched"
	if [ -n "$blocked" ]; then
		_patch_refuse "local edits on touched files" \
			"The patch rewrites files you have edited. Commit or discard them first:" \
			"$(echo "$blocked" | sed 's/^/  /')" \
			"(pwt never stashes for you)"
		return $?
	fi

	# A file the patch creates that already exists untracked would be
	# overwritten by git am and lost
	local collisions=""
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		[ -e "$path/$f" ] || continue
		# A typechange (file to symlink) is a delete plus a create of a
		# tracked path: git handles that one itself
		git -C "$path" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && continue
		collisions="${collisions:+$collisions$'\n'}$f"
	done <<<"$creates"
	if [ -n "$collisions" ]; then
		_patch_refuse "the patch creates files that already exist" \
			"Move or remove them first:" \
			"$(echo "$collisions" | sed 's/^/  /')"
		return $?
	fi

	if [ "$_PATCH_ALLOW_SECRETS" != true ]; then
		local secrets="" glob
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			for glob in $PWT_PATCH_SECRET_GLOBS; do
				# shellcheck disable=SC2254  # the glob is the point
				case "$f" in
				$glob | */$glob) secrets="${secrets:+$secrets$'\n'}$f" ;;
				esac
			done
		done <<<"$touched"
		if [ -n "$secrets" ]; then
			_patch_refuse "the patch touches secret paths" \
				"$(echo "$secrets" | awk '!seen[$0]++' | sed 's/^/  /')" \
				"Pass --allow-secrets if that is intended."
			return $?
		fi
	fi

	local running
	running=$(_patch_running_jobs "$name")
	if [ -n "$running" ]; then
		if [ "$_PATCH_IDLE" = true ]; then
			_patch_refuse "$name has running pwt jobs: $running" \
				"Stop them first (pwt jobs stop <id>), or apply without --idle."
			return $?
		fi
		_patch_say "${YELLOW}Warning: $name has running pwt jobs: $running (a server reloads when its files change)${NC}"
	fi

	# ---- the backup, then the apply -------------------------------------
	PATCH_BACKUP_NAME=""
	_patch_backup "$name" "$path" "$head_before"
	local undo="git -C $path reset --keep $head_before"

	local repair_available=false
	has_pwtfile_command "repair" && repair_available=true

	if [ "$_PATCH_KIND" = diff ]; then
		local staged_result=false
		if git -C "$path" apply --check $_PATCH_PLEVEL "$apply_file" >"$tmp/apply.out" 2>&1; then
			git -C "$path" apply $_PATCH_PLEVEL "$apply_file" >"$tmp/apply.out" 2>&1 || {
				pwt_error "Error: git apply failed after --check passed"
				sed 's/^/  /' "$tmp/apply.out" >&2
				return $EXIT_ERROR
			}
		elif git -C "$path" apply --3way $_PATCH_PLEVEL "$apply_file" >"$tmp/apply.out" 2>&1; then
			staged_result=true
		else
			local conflicts
			conflicts=$(git -C "$path" diff --name-only --diff-filter=U 2>/dev/null)
			git -C "$path" reset -q --keep "$head_before" 2>/dev/null || true
			while IFS= read -r f; do
				[ -n "$f" ] || continue
				git -C "$path" checkout -q -- "$f" 2>/dev/null || true
			done <<<"$touched"
			pwt_error "Aborted: the diff does not apply to $name"
			sed 's/^/  /' "$tmp/apply.out" | head -n 20 >&2
			if [ "$_PATCH_JSON" = true ]; then
				_patch_emit_apply_json aborted "diff does not apply" "$head_before" "$head_before" "" 0 "$touched" "" "$conflicts" "$PATCH_BACKUP_NAME" "$undo" "$repair_available"
			fi
			return $EXIT_ERROR
		fi
		_patch_say "${GREEN}✓ Applied the diff to $name (no commit)${NC}"
		_patch_say "  Files: $(echo "$touched" | tr '\n' ' ')"
		[ "$staged_result" = true ] && _patch_say "  ${YELLOW}Needed a 3-way merge: the result is staged, read it before committing${NC}"
		_patch_say "  Backup: $PATCH_BACKUP_NAME (pwt restore lists it)"
		if [ "$_PATCH_JSON" = true ]; then
			_patch_emit_apply_json applied "" "$head_before" "$head_before" "" 0 "$touched" "" "" "$PATCH_BACKUP_NAME" "git -C $path checkout -- ." "$repair_available"
		fi
		return 0
	fi

	local am_out="$tmp/am.out"
	if ! git -C "$path" am -3 $_PATCH_PLEVEL "$apply_file" >"$am_out" 2>&1; then
		local conflicts failed_at
		conflicts=$(git -C "$path" diff --name-only --diff-filter=U 2>/dev/null)
		failed_at=$(sed -n 's/^Patch failed at [0-9]* //p' "$am_out" | head -n 1)
		git -C "$path" am --abort >/dev/null 2>&1 || true
		if [ "$(git -C "$path" rev-parse HEAD 2>/dev/null)" != "$head_before" ]; then
			git -C "$path" reset -q --keep "$head_before" 2>/dev/null || true
		fi
		local reason="conflict"
		if grep -q -E 'lacks the necessary blob|sha1 information is lacking' "$am_out"; then
			reason="base commit missing in this repository"
		fi
		pwt_error "Aborted: ${failed_at:+patch \"$failed_at\": }$reason"
		if [ "$reason" = conflict ] && [ -n "$conflicts" ]; then
			echo "  Conflicting files:" >&2
			echo "$conflicts" | sed 's/^/    /' >&2
		elif [ "$reason" != conflict ]; then
			echo "  The 3-way merge needs the commits the patch was made on. Fetch them, then apply again." >&2
		fi
		grep -E '^(error|fatal):' "$am_out" | grep -v 'Failed to merge in the changes' | head -n 5 | sed 's/^/  /' >&2
		echo "  $name is back at ${head_before:0:7}; nothing was applied." >&2
		if [ "$_PATCH_JSON" = true ]; then
			_patch_emit_apply_json aborted "$reason" "$head_before" "$head_before" "" "$skipped" "$touched" "" "$conflicts" "$PATCH_BACKUP_NAME" "$undo" "$repair_available"
		fi
		return $EXIT_ERROR
	fi

	# ---- the result -----------------------------------------------------
	local head_after applied changed three_way count
	head_after=$(git -C "$path" rev-parse HEAD)
	applied=$(git -C "$path" log --reverse --format='%H %s' "$head_before..$head_after" 2>/dev/null)
	changed=$(git -C "$path" diff --name-only "$head_before" "$head_after" 2>/dev/null)
	three_way=$(sed -n 's/^Auto-merging //p' "$am_out" | awk '!seen[$0]++')
	count=0
	[ -n "$applied" ] && count=$(printf '%s\n' "$applied" | grep -c .)

	local branch
	branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "detached")
	local noun="commits"
	[ "$count" -eq 1 ] && noun="commit"
	if [ "$skipped" -gt 0 ]; then
		_patch_say "${GREEN}✓ Applied $count $noun to $name${NC} ($branch), skipped $skipped (already in branch)"
	else
		_patch_say "${GREEN}✓ Applied $count $noun to $name${NC} ($branch)"
	fi
	if [ -n "$applied" ]; then
		printf '%s\n' "$applied" | while IFS= read -r line; do
			_patch_say "  ${line:0:7} ${line#* }"
		done
	fi
	[ -n "$changed" ] && _patch_say "  Files: $(echo "$changed" | tr '\n' ' ')"
	[ -n "$three_way" ] && _patch_say "  ${YELLOW}3-way merged (read these): $(echo "$three_way" | tr '\n' ' ')${NC}"
	_patch_say "  Backup: $PATCH_BACKUP_NAME (pwt restore lists it)"
	_patch_say "  Undo:   $undo"

	export PWT_CHANGED_FILES="$changed"
	export PWT_PREVIOUS_COMMIT="$head_before"
	if [ "$repair_available" = true ] && [ "$count" -gt 0 ]; then
		if [ "$_PATCH_REPAIR" = true ]; then
			_patch_say "${BLUE}Repairing: $name${NC}"
			export PWT_WORKTREE="$name"
			export PWT_WORKTREE_PATH="$path"
			export PWT_PORT
			PWT_PORT=$(get_metadata "$name" "port" 2>/dev/null || echo "")
			export PWT_BRANCH="$branch"
			(
				cd "$path" || exit 1
				if [ "$_PATCH_JSON" = true ]; then
					run_pwtfile "repair" >&2
				else
					run_pwtfile "repair"
				fi
			)
		else
			_patch_say "  Repair: pwt repair $name  (the Pwtfile has repair(); it sees PWT_CHANGED_FILES)"
		fi
	fi

	if [ "$_PATCH_JSON" = true ]; then
		_patch_emit_apply_json applied "" "$head_before" "$head_after" "$applied" "$skipped" "$changed" "$three_way" "" "$PATCH_BACKUP_NAME" "$undo" "$repair_available"
	fi
	return 0
}

_patch_export() {
	local wt=""
	case $# in
	0) ;;
	1) wt="$1" ;;
	*)
		pwt_error "Error: too many arguments"
		echo "Usage: pwt patch export [<worktree>] [--base <ref>] [-o <file>]" >&2
		return $EXIT_USAGE
		;;
	esac
	if [ "$_PATCH_JSON" = true ] && [ -z "$_PATCH_OUT" ]; then
		pwt_error "Error: --json needs -o <file>: stdout carries the JSON, not the patch"
		return $EXIT_USAGE
	fi
	_patch_resolve_worktree "$wt" || return $?
	local name="$PATCH_WT_NAME" path="$PATCH_WT_PATH"

	local base base_label
	if [ -n "$_PATCH_BASE" ]; then
		base=$(git -C "$path" rev-parse --verify "$_PATCH_BASE^{commit}" 2>/dev/null) || {
			pwt_error "Error: base ref not found in $name: $_PATCH_BASE"
			return $EXIT_NOT_FOUND
		}
		base_label="$_PATCH_BASE"
	else
		local base_ref
		base_ref=$(get_metadata "$name" "base" 2>/dev/null || echo "")
		[ -n "$base_ref" ] || base_ref="${DEFAULT_BRANCH:-master}"
		base=$(git -C "$path" merge-base HEAD "$base_ref" 2>/dev/null) || {
			pwt_error "Error: cannot find where $name forked from $base_ref; pass --base <ref>"
			return $EXIT_NOT_FOUND
		}
		base_label="merge base with $base_ref"
	fi

	local count merges
	count=$(git -C "$path" rev-list --count --no-merges "$base..HEAD" 2>/dev/null || echo 0)
	merges=$(git -C "$path" rev-list --count --merges "$base..HEAD" 2>/dev/null || echo 0)
	local noun="commits"
	[ "$count" -eq 1 ] && noun="commit"
	echo -e "${BLUE}$count $noun from $name${NC} (base ${base:0:7}, $base_label)" >&2
	if [ "$merges" -gt 0 ]; then
		local mnoun="merge commits"
		[ "$merges" -eq 1 ] && mnoun="merge commit"
		echo -e "${YELLOW}Warning: the range has $merges $mnoun; format-patch leaves them and their resolutions out${NC}" >&2
	fi

	local output="${_PATCH_OUT:--}"
	if [ "$count" -gt 0 ]; then
		if [ -n "$_PATCH_OUT" ]; then
			git -C "$path" format-patch --stdout --binary "$base..HEAD" >"$_PATCH_OUT" || {
				pwt_error "Error: git format-patch failed"
				return $EXIT_ERROR
			}
			echo -e "${GREEN}✓ Wrote $_PATCH_OUT${NC}" >&2
		else
			git -C "$path" format-patch --stdout --binary "$base..HEAD" || {
				pwt_error "Error: git format-patch failed"
				return $EXIT_ERROR
			}
		fi
	else
		echo "Nothing written." >&2
	fi

	if [ "$_PATCH_JSON" = true ]; then
		printf '{"schema_version":1,"command":"patch export","project":"%s","worktree":"%s","path":"%s","base":"%s","head":"%s","commits":%s,"merges":%s,"output":"%s"}\n' \
			"$(json_escape "$CURRENT_PROJECT")" "$(json_escape "$name")" "$(json_escape "$path")" \
			"$base" "$(git -C "$path" rev-parse HEAD)" "$count" "$merges" \
			"$(json_escape "$([ "$count" -gt 0 ] && echo "$output")")"
	fi
	return 0
}
